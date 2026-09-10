/*
spamfilter for Apple Mail.app on macOS
Copyright (c) 2026 Christian Sturm

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/


'use strict';

// start web inspector panel
//debugger

var shouldAlertMatchDetails = false  // true: alert rule item if a rule match is found
var shouldLogActivity = false  // true: log details about message tests to file
const mutexLifetime = 120  // duration in seconds after which a mutex lock will be reset


const mail = Application.currentApplication().name == "Mail"
	? Application.currentApplication() : Application("Mail")
mail.includeStandardAdditions = true
if (!mail.running()) {
	delay(10)
	if (!mail.running()) throw "Mail.app not running"
}


ObjC.import('Foundation')
ObjC.import('stdlib')
ObjC.import('stdio')
ObjC.import('unistd')
//ObjC.import('dispatch')

var rulesHandler = new RulesHandler()


/** These chars are usually not used within normal text,
	but to prevent word-based blacklisting in spam.
	e.g. zero-width spaces like byte order mark
*/
const cheatChars = ['\uFEFF','\u200B', '\u200C', '\u2060']

/** uncommon file extensions */
const fileExtensions = ['.7z', '.exe', '.jpg.zip']

/** uncommon charsets (in lowercase) */
const charsetBlacklist = ['windows-1251'/* cyrillic*/, 'gb2312'/*chinese*/, 'gb18030'/*chinese*/]


/** Construct blacklist rules handler */
function RulesHandler(path = null) {
	this.rulesList = null
	if (path)
		this.path = path
	else {
		this.path = mail.pathTo("library folder", {from: "user domain", folderCreation: false}).toString() + "/Application Scripts/com.apple.mail/spamfilter-rules.json"
	}
}

/** Load json object from rules file */
RulesHandler.prototype.loadConfigFromFile = function() {
	var config = null,
		fm = $.NSFileManager.defaultManager
	if (!fm.fileExistsAtPath(this.path)) {
		alertError("No rules file found!", {givingUpAfter: 10})
		return config
	}
	var contents = fm.contentsAtPath(this.path) // NSData
	contents = $.NSString.alloc.initWithDataEncoding(contents, $.NSUTF8StringEncoding);
	var configJsonStr = ObjC.unwrap(contents)
	
	if (configJsonStr != "")
		config = JSON.parse(configJsonStr)
	else
		console.log("No rules in file!")
	return config
}

/** Setup rules and configuration from json object */
RulesHandler.prototype.loadRulesList = function() {
	if (this.rulesList !== null) return true

	try {
		var config = this.loadConfigFromFile()
	} catch (e) {
		console.log(e.name +': '+ e.message)
		if (e instanceof SyntaxError && !config)
			alertError("JSON syntax error in rules file on line "+ e.lineNumber +": "
				+ e.message)
	}
	
	if (!config || !config.rulesList) return false
	
	if (config.shouldAlertMatchDetails === true || config.shouldAlertMatchDetails === "true")
		shouldAlertMatchDetails = config.shouldAlertMatchDetails
	if (config.shouldLogActivity === true || config.shouldLogActivity !== "false")
		shouldLogActivity = config.shouldLogActivity
	
	this.rulesList = config.rulesList
	return true
}

/** Get rules for given email address resp. account */
RulesHandler.prototype.getRulesForAddress = function(address) {
	return this.rulesList.find(function(rule) {
		return address === rule.email
	})
}

/** Get rules for given account name */
RulesHandler.prototype.getRulesForAccount = function(name) {
	return this.rulesList.find(function(rule) {
		return name === rule.accountName
	})
}


/** handler called by terminal via osascript -l JavaScript <path> */
function run () {
	mail.downloadHtmlAttachments = false
	
	// only run if not invoked by Mail.app
	if (Application.currentApplication().name != "Mail" && !CliMode.isCliMode) {
		//console.log('cli mode')
		CliMode()
	}
	
	const accountList = Account.getAccountList()  //mail.accounts()
	var shouldDisplayNotification = false
	if (!rulesHandler.loadRulesList()) return
	
	accountList.forEach(function(account){
		if (!account.enabled) return
		
		const filterHandler = new SpamFilterHandler(account)
		//filterHandler.account = new Account(account)
		if (!filterHandler.loadAccountRules()) {
			//ActivityLog.log("no-rules/"+ filterHandler.account.emailAddressList[0] +" (CLI invoked)")
			return
		}
		
		const accountMutex = new RunCoordinator(filterHandler.account.id)
		if (accountMutex.tryLock() !== true) {
			ActivityLog.log("CLI:no-lock/"+ filterHandler.accountRules.email)
			return
		}
		
		//ActivityLog.log("got-lock/"+ filterHandler.accountRules.email +" (CLI invoked)")
		
		filterHandler.invokedBy = 'CLI:';
		filterHandler.filterAccountMailboxes()
		shouldDisplayNotification ||= filterHandler.hasNewMessages
		accountMutex.unlock()
	})
	ActivityLog.finish()
	if (shouldDisplayNotification) newMailNotification()
}

/** handler called by Apple Mail when applying rules on messages */
function performMailActionWithMessages (messages, manualProperties) {
	mail.downloadHtmlAttachments = false
	if (!rulesHandler.loadRulesList()) return
	
	// skip remaining messages if identical to first one due to bug in Mail.app
	// wrap Mail JXA API
	var messageList = null
	if (messages.length > 1 && messages[0].id() !== messages[1].id())
		messageList = messages.map((raw) => {return new Message(raw)})
	else
		messageList = [new Message(messages[0])]
	const firstMsg = messageList[0],
		firstMailbox = firstMsg.mailbox,
		firstAddress = firstMailbox.account.emailAddressList[0] || firstMailbox.account.name
	
	const filterHandler = new SpamFilterHandler()
	filterHandler.initMailboxFilter(firstMailbox)
	
	// race condition bug after startup of Mail.app often takes the latest already received message as first item and messes up its properties => detect and skip
	const lookedUpMsg = firstMailbox.getMessageById(firstMsg.id)
	if (lookedUpMsg && lookedUpMsg.readStatus === true) {
		messageList = messageList.slice(1)
		ActivityLog.log("skip-old-msg/"+ firstAddress +'/id.'+ firstMsg.id)
	}
	
	filterHandler.filterMessageList(messageList)
	
	// return if no rules exist
	/*if (!filterHandler.mailboxRule) {
		ActivityLog.finish()
		return
	}*/
	
	/* no bug circumvention needed if only one message in list or user-selected list,
	   already in trash or other spamfilter instance running on account
	*/
	// try to get lock of current account if more messages are available to filter
	const accountMutex = new RunCoordinator(firstMailbox.account.id)
	if (messageList.length > 1  // user-selected list
	  || ["Deleted Messages", "Trash"].includes(firstMailbox.name)
	  || accountMutex.trySpinLock() !== true) {
		if (accountMutex.gotLock() === false)
			ActivityLog.log("no-lock/"+ firstAddress)
		ActivityLog.finish()
		return
	}
	if (accountMutex.gotLock() === true)
		ActivityLog.log("got-lock/"+ firstAddress)
	
	// filter messages not dealt with above due to bugs in Mail.app
	// => filter the whole mailbox of the first message given in messages arg
	mail.checkForNewMail()
	delay(2)
	//filterHandler.mailbox.refreshMessageList()
	if (messages.length > 1 || (filterHandler.mailbox && filterHandler.mailbox.unreadCount >0))
		filterHandler.filterCurrentMailbox()
	
	// also filter custom mailboxes having some rules defined
	filterHandler.filterAccountMailboxes()
	
	accountMutex.unlock()
	ActivityLog.finish()
	if (filterHandler.hasNewMessages) newMailNotification()
}

/** called at the end of script execution */
function quit() {
	RunCoordinator.unlockAll()
	ActivityLog.finish()
	$.exit(0)
}

/** Display notification for new messages in mailboxes other than INBOX */
function newMailNotification(retryOnError = true) {
	const app = Application.currentApplication()  // displayNotification only works in currApp
	app.includeStandardAdditions = true
	try {
		app.displayNotification('New messages in Mail.app', {withTitle: "Spamfilter"})
	} catch (err) {
		console.log("Notification error: "+ err.message)
		try {  // try again with mail app handle
			mail.displayNotification('New messages in Mail.app', {withTitle: "Spamfilter"})
		} catch (err) {
			if (retryOnError) newMailNotification(false)
		}
	}
}

/** Handles all spam filter operations on single messages, message lists, mailboxes and accounts
*/
function SpamFilterHandler (account = null) {
	this.mailbox = null
	this.mailboxRule = null
	this.accountRules = null
	this.account = account
	this.accountMailboxes = null
	this.invokedBy = ''
	this.hasNewMessages = false
}
/** Applies spam filter operation on given message list;
	Defines mailbox, rules and account properties for subsequent filtering
*/
SpamFilterHandler.prototype.filterMessageList = function(messageList) {
	if (!Array.isArray(rulesHandler.rulesList)) {
		alertError("No rules list found in json file")
		return
	}
	
	for (var message of messageList) {
		// search matching rule based on email address
		const mailbox = message.mailbox
		const rule = this.getRuleAndAccountFromMailbox(mailbox)
	
		if (!rule) {
			ActivityLog.log(`no-rules/${this.account.emailAddressList[0] || this.account.name}/box.${mailbox.name}`)
			return
		}
		
		if (Progress) Progress.description = rule.email
		
		ActivityLog.logMessage(message, "firstrun-test/"+ rule.email)
		this.filterMessage(rule, message)
	}
}

/** Get account rules from general rules list */
SpamFilterHandler.prototype.loadAccountRules = function() {
	if (!this.account) {
		ActivityLog.log("loadAccountRules() failed: this.account not defined")
		return false
	}
	
	const accountAddressList = this.account.emailAddressList
	
	// search account specific rules object
	var accountRules = null
	for (let address of accountAddressList) {
		if (accountRules = rulesHandler.getRulesForAddress(address)) break
	}
	if (!accountRules) {
		if (!accountAddressList || accountAddressList.length === 0)
		  ActivityLog.log("loadAccountRules(): no addresses defined for account "+ this.account.name)
		// retry to find rules by account name if specified
		accountRules = rulesHandler.getRulesForAccount(this.account.name) 
	}
	if (!accountRules) return false
	this.accountRules = accountRules
	if (!accountRules.mailboxList) accountRules.mailboxList = []
	
	// add default INBOX rule to mailboxList if not already included
	//let names = ''
	const inbox = this.account.mailboxList.find((box) => {
		//names += box.name+', '
		return box.name == 'INBOX' || box.name == 'Inbox'
	})
	//alertInfo(names)
	if (!inbox) return true  // unknown inbox => skip
	if (accountRules.mailboxList.some(function(rule){
		return rule.name === inbox.name
	})) return true
	
	accountRules.mailboxList.push({
		name: inbox.name,
		email: accountRules.email,
		trustList: accountRules.trustList,
		fromWhitelist: accountRules.fromWhitelist,
		senderBlacklist: accountRules.senderBlacklist,
		subjectBlacklist: accountRules.subjectBlacklist,
		contentBlacklist: accountRules.contentBlacklist,
		headerBlacklist: accountRules.headerBlacklist
	})
	return true
}

/** Returns the correct rule in json rules file for given mailbox;
	Sets account rule set
*/
SpamFilterHandler.prototype.getRuleAndAccountFromMailbox = function(mailbox) {
	this.account = mailbox.account
	const boxName = mailbox.name
	
	if (!this.loadAccountRules()) return null;
	
	// choose either the default rule for INBOX or one for cutom mailboxes
	let rule = null
	if (Array.isArray(this.accountRules.mailboxList)
		  && this.accountRules.mailboxList.length > 0) {
		rule = this.accountRules.mailboxList.find(function(rule){
			return boxName === rule.name
		})
		if (rule) rule.email = this.accountRules.email
	}
	return rule
}

/** Sets the handler's mailbox and mailboxRule properties using values from given message
*/
SpamFilterHandler.prototype.initMailboxFilter = function(mailbox) {
	const rule = this.getRuleAndAccountFromMailbox(mailbox)
	if (!rule) return
	
	this.mailbox = mailbox
	this.mailboxRule = rule
}

/** Applies spam filter operation on given message */
SpamFilterHandler.prototype.filterMessage = function(rule, message) {
	var trustRes = testTrustPolicies(rule.trustList, message)
	
	// message is fully trusted by policies
	if (trustRes.violated === false && !trustRes.shouldProceed  && !trustRes.isBorderline)
		return false
	
	// found suspicious edge cases in policies => flag message to inform user, no deletion
	if (trustRes.violated === false && trustRes.isBorderline) {
		if (trustRes.onViolation === 'flag') {
			message.junkMailStatus = true
			this.flagMessage(message)
		}
		if (!trustRes.shouldProceed) return false
	}
	
	if (trustRes.violated || testSelfAddressedForFullName(rule.email, message)
		 || testSenderForFullName(rule.fromWhitelist, message)
		 || testMessageFieldBySimilarity('from', rule.senderBlacklist.similarityList, message)
		 || testMessageField('from', rule.senderBlacklist, message)
		 || testMessageField('subject', rule.subjectBlacklist, message)
		 || testHeaders(rule.headerBlacklist, message)
		 || testMessageField('source', rule.contentBlacklist, message)) {
		// delete message as soon as a blacklist match is detected
		 
		// mark message as processed by spamfilter for debugging
		/*message.flagIndex = 6;	// gray
		message.flaggedStatus = true;*/
		message.junkMailStatus = true
		
		if (trustRes.violated && (trustRes.onViolation || rule.trustList.onViolation) === 'flag') {
			this.flagMessage(message)
		} else {
			this.moveToTrash(message)
		}
		
		delay(0.5)  // avoid DoS of your mail server
		return true
	} else {
		//console.log("No blacklist matches found")
		//alertInfo("No blacklist matches found")
		return false
	}
}
/** flag message with color */
SpamFilterHandler.prototype.flagMessage = function(message) {
	message.flagIndex = 0  // 0: red, 6: grey
	message.flaggedStatus = true
}
/** moves specified message to trash folder of its mail account */
SpamFilterHandler.prototype.moveToTrash = function(mes) {
	//mes.junkMailStatus = true
	//mes.deletedStatus = true // message lost in the Nirwana

	if (!this.account) alertError("Account of mailbox undefined")
	
	// get trash mailbox of account
	const boxList = this.accountMailboxes || (this.accountMailboxes = this.account.mailboxList)
	if (!boxList || boxList.length === 0) alertError("Mailbox list undefined")
	
	var trash = boxList.find(function(box){
		const boxName = box.name, exists = boxName.includes("Deleted Messages")
		return exists || boxName.includes("Trash")
	});
	if (!trash) {
		alertError("Trash undefined for account " + this.account.name)
		return
	}

	mes.moveToMailbox(trash)
	//mail.checkForNewMail(account)
}


/** Applies spam filter operation once on given mailbox using given rule */
SpamFilterHandler.prototype.filterMailbox = function(boxRule, mailbox) { 
	const unreadList = mailbox.getUnreadMessageList()
	if (unreadList.length == 0) return undefined
	//alertInfo(unreadList.length +': '+ unreadList[0].getField('from'))
	var succeeded = true  // becomes false on (readStatus) error
	succeeded = unreadList.every((message, msgIdx) => {
		const readStatus = message.readStatus
		if (readStatus === null || readStatus === undefined) {
			ActivityLog.log("readStatus = null/undefined for idx."+ msgIdx)
			//succeeded = false
			return false
		}
		
		ActivityLog.logMessage(message, this.invokedBy +"secrun-test/"+ boxRule.email +"/idx."
			+ msgIdx)
		
		// test unread message
		if (!readStatus) {
			this.filterMessage(boxRule, message)
		}
		return true
	})
	return succeeded
	
	/*  // implementation working on unfiltered message list
	// message list: chronological merge of 'Deleted Messages' since startup and 'INBOX'
	var  msgIdx = 0, unreadCount = mailbox.unreadCount, initMessageCount = mailbox.messageCount
	while (msgIdx < unreadCount && msgIdx < mailbox.messageCount
	  && mailbox.messageCount == initMessageCount) {
		const message = mailbox.getMessageByIndex(msgIdx),
			readStatus = message.readStatus
		if (readStatus === null || readStatus === undefined) {
			ActivityLog.log("readStatus = null/undefined")
			mailbox.refreshMessageList()
			return false
		}
		const junkStatus = message.junkMailStatus
			
		ActivityLog.logMessage(message, this.invokedBy +"secrun-test/"+ boxRule.email +"/idx."
			+ msgIdx)
		
		// don't count already tested spam messages or read messages
		if (junkStatus || readStatus) unreadCount++
		
		// test message (again)
		if (!readStatus) {
			this.filterMessage(boxRule, message)
			if (mailbox.unreadCount === 0) break
		}
		
		msgIdx++
		
		// watchdog for Mail.app bugs, e.g., new message not yet in messages list of mailbox
		// causing big useless message loop
		if (msgIdx % 5 == 0) {
			if (Date.now() - Date.parse(message.getField('dateReceived')) > 86400000*20) {
				ActivityLog.log("stop filtering: messages older than 20 days")
				break
			}
			mailbox.refreshMessageList()
		}
	}
	return true*/
}

/** Applies spam filter operation on predefined mailbox, e.g., by filterMessageList().
	This method is more reliable than filterMailbox() alone due to bugs in Mail.app
*/
SpamFilterHandler.prototype.filterCurrentMailbox = function() {
	if (!this.mailbox || !this.account) return
	
	this.accountMailboxes = this.account.mailboxList
	this.filterMailboxInLoops(this.mailboxRule, this.mailbox)
}

/** Applies multiple iterations of spam filter operation on given mailbox using given rule */
SpamFilterHandler.prototype.filterMailboxInLoops = function(boxRule, mailbox) {
	// try multiple times to catch all unread messages in INBOX
	var iterations = 2, remainingErrorRetries = 4
	for (var i=0; i<iterations; i++) {
		delay(0.5)
		var unreadCount = mailbox.unreadCount
		if (unreadCount == 0) break
		
		ActivityLog.log(this.invokedBy +"more-messages/"+ boxRule.email +"/box."
			+ mailbox.name +"/loop."+ i +": " + unreadCount)
		if (Progress) Progress.description = boxRule.email +": Mailbox test"
		
		const res = this.filterMailbox(boxRule, mailbox)
		if (res === false && remainingErrorRetries-- > 0)  // property read error
			iterations++
		else if (!res && iterations == 2) iterations = 3  // empty message list
	}
	
	// display notification if new messages in secondary mailboxes
	if (mailbox.name == 'INBOX' || mailbox.name == 'Inbox') return
	if (mailbox.unreadCount > 0) this.hasNewMessages = true
}

/** Applies spam filter operation on custom mailboxes of predefined account */
SpamFilterHandler.prototype.filterAccountMailboxes = function() {
	if (!this.account || !this.accountRules || !this.accountRules.mailboxList) return
	
	this.accountMailboxes = this.account.mailboxList
	const firstMsgBoxName = this.mailbox ? this.mailbox.name : null
	this.accountRules.mailboxList.forEach(function(boxRule){
		if (boxRule.name === firstMsgBoxName) return
		
		var mailbox = this.accountMailboxes.find(function(box){
			return box.name === boxRule.name
		})
		if (!mailbox) return
		
		boxRule.email = this.accountRules.email
		this.filterMailboxInLoops(boxRule, mailbox)
	}, this)
}


/** log all message tests in separate file for debugging if shouldLogActivity == true */
const ActivityLog = (function() {
	/*if (!shouldLogActivity) {
		// return dummy methods if logging switched off
		const dummyFnc = function(){}
		return {log: dummyFnc,
		  logMessage: dummyFnc,
		  finish: dummyFnc
		}
	}*/
	
	const path = ObjC.wrap(mail.pathTo("library folder", {from: "user domain", folderCreation: false}).toString() + "/Application Scripts/com.apple.mail/spamfilter.log")
		.stringByStandardizingPath
	var fh = $.NSFileHandle.fileHandleForWritingAtPath(path)
	if (fh.isNil()) {
		console.log("create new log file")
       	$.NSFileManager.defaultManager.createFileAtPathContentsAttributes(path, undefined, undefined)
       	fh = $.NSFileHandle.fileHandleForWritingAtPath(path)
    }
	if (fh.isNil()) {
		console.log("couldn't get file handle for logging")
		return
	}
	fh.seekToEndOfFile
	
	try {
		// redirect stderror output to log file
		const stderrFd = $.NSFileHandle.fileHandleWithStandardError.fileDescriptor
		//$.freopen(path.UTF8String, ObjC.wrap("a+").UTF8String, stderrFd)
		$.dup2(fh.fileDescriptor, stderrFd)
	} catch (e) {
		console.log(e.message)
	}
	
	/** general log function appending entry as a line to file */
	var log = function(str) {
		if (!shouldLogActivity) return
		
		try {
			fh.seekToEndOfFile
			fh.writeData(ObjC.wrap(str +"\n").dataUsingEncoding($.NSUTF8StringEncoding))
		} catch (e) {
			console.log("failed writing to log file: "+ e.name +", "+ e.message)
			alertError("failed writing to log file: "+ e.name +", "+ e.message)
			return false
		}
		return true
	}
	
	/** log given message along with run type of test */
	var logMessage = function(msg, runType) {
		if (!shouldLogActivity) return
	
		const receivedArr = msg.getField('received').trim().split(' ', 2)
		log(runType +",ts."+ Date.now() +": "+ msg.getField('dateReceived')
		  +",id."+ msg.id
		  +",box."+ msg.mailbox.name
		  +","+ msg.getField('from')
		  +", rcvd:"+ receivedArr.join(' ')
		  +", "+ msg.getField('subject')
		)
	}
	
	/** close file before quit */
	var finish = function() {
		if (!shouldLogActivity) return
		
		try {
			fh.closeFile
		} catch (e) {
			console.log("failed closing log file: "+ e.name +", "+ e.message)
		}
	}
	
	return {log: log,
		  logMessage: logMessage,
		  finish: finish
	}
})()

/** manages mutex locks accessible to different spamfilter instances (osascript processes) */
const RunCoordinator = (function() {
	const dir = mail.pathTo("library folder", {from: "user domain", folderCreation: false}
		).toString() + "/Application Scripts/com.apple.mail/"
	//var path = '', mutex = null, gotLock = null
	
	/** constructor creates path to mutex file */
	function RunCoordinator(resourceId) {
		this._mutex = null
		this._gotLock = null
		this._path = ObjC.wrap(dir +'.'+ resourceId +'.spamfilter.lock') 
	}
	
	/** try to get lock for specified resource id and return result */
	RunCoordinator.prototype.tryLock = function() {
		this._mutex = $.NSDistributedLock.lockWithPath(this._path)

		// force unlock if older than mutexLifetime (600) sec as normal unlocking seemed to fail
		if (!this._mutex.lockDate.isNil()) {
			// Foundation.fw bug: lockDate set to reference date (docs say nil) if no lock present
			var nowIntvl = Math.abs(ObjC.unwrap(this._mutex.lockDate.timeIntervalSinceNow)),
				refIntvl = ObjC.unwrap(this._mutex.lockDate.timeIntervalSinceReferenceDate)
			if (nowIntvl < refIntvl && nowIntvl > mutexLifetime)
				this._mutex.breakLock
		}
		
		try {
			this._gotLock = ObjC.unwrap(this._mutex.tryLock)
		} catch (e) {
			console.log("mutex locking error: "+ e.message)
		}
		if (this._gotLock) RunCoordinator._instanceList.push(this)
		return this._gotLock
	}
	
	/** tries multiple times to lock with wait time in between */
	RunCoordinator.prototype.trySpinLock = function() {
		for (let i=0; i<2; i++) {
			if (this.tryLock() === true) return true
			
			delay(2)
			if (i == 1) return false
		}
	}
	
	/** returns true if got lock else false; null if tryLock() not yet called */
	RunCoordinator.prototype.gotLock = function() {
		return this._gotLock
	}
	
	/** unlock existing mutex */
	RunCoordinator.prototype.unlock = function() {
		if (this._mutex) {
			this._mutex.unlock
			this._gotLock = false
		}
	}
	
	RunCoordinator._instanceList = []
	RunCoordinator.unlockAll = function() {
		console.log('unlock all')
		RunCoordinator._instanceList.forEach((coordinator) => {
			//alertInfo(JSON.stringify(coordinator) + ', ' + (typeof coordinator))
			if (coordinator._gotLock) coordinator.unlock()
		})
		RunCoordinator._instanceList = []
	}
		
	return RunCoordinator
})()

/** alert item that matched a rule; useful for enhancing rules */
function alertMatchDetails (field, item = null) {
	if (!shouldAlertMatchDetails) return
	try {
		mail.displayDialog(field + (item !== null ? ': '+ item : ''), {withTitle: 'Spamfilter match details'})
	} catch (err) {
		ActivityLog.log('script aborted by user')
		quit()
	}
}

/** alert error to user */
function alertError (msg, options = {}) {
	mail.displayDialog(msg, Object.assign({withTitle: 'Spamfilter error', withIcon: "caution"}, options))
}

/** alert uncritical info to user */
function alertInfo (msg, options = {}) {
	mail.displayDialog(msg, Object.assign({withTitle: 'Spamfilter info', withIcon: "note"}, options))
}

/** returns spam match (true) if policy for the given selector (name in 'From' field) is invalid
	policy may include: comma-separated list of allowed 'From' addresses; DKIM, SPF header; Authentication-Results header; other header with matching components */
function testTrustPolicies (trustConfig, message) {
	if (!trustConfig || !trustConfig.list) return {violated: false, shouldProceed: true}
	const trustList = trustConfig.list
	
	// find match between selector and 'From' header
	const from = message.getField('from'),
		canonicalFrom = Utils.canonicalize(from)
	const selectorQuery = (trustedEntity) => {
		if (!trustedEntity._similarity) {
			// transform trustedEntity from json to TrustedEntity object type
			// reduce number of necessary canonicalize() calls through lazy evaluation
			try {
			  TrustedEntity.applyRuntimeProperties(trustedEntity, trustConfig)
			} catch (err) {  // catches configuration errors caused by the user
			  alertError(error.message)
			  return false
			}
		}
		
		const hasSelectorMatched = trustedEntity.selectorHasMatched(canonicalFrom)
		
		// additional receiver address for selector match
		const hasReceiverMatched = !trustedEntity.receiverAddress
		  || message.getField('to').trim().toLowerCase() == trustedEntity.receiverAddress
		
		return hasSelectorMatched && hasReceiverMatched
	}
	var matchedSelectorList = []
	
	if (trustConfig.selectorMode && trustConfig.selectorMode == 'relaxed') {
		// relaxed mode: first matching selector object doesn't have to succeed, but others do
		matchedSelectorList = trustList.filter(selectorQuery, this)
	} else {  // default: strict selector mode, i.e., first matching selector must succeed
		const selector = trustList.find(selectorQuery, this)
		if (selector) matchedSelectorList.push(selector)
	}
	// no selector match?
	if (matchedSelectorList.length == 0) return {violated: false, shouldProceed: true}
	
	var shouldProceedTests = false,
		isBorderline = false,
		onViolation = null
	
	// test policies
	const violated = matchedSelectorList.every((trustedEntity, entityIdx) => {
		if (!trustedEntity.policyList || !Array.isArray(trustedEntity.policyList)) {
			alertError('No policy list found for selector '+ trustedEntity.selector)
			return false
		}
		
		// find appropriate policy through address matching
		const selectedPolicy = trustedEntity.policyList.find((policy) => {
			// test 'From' email address if specified comma-separated list of allowed addresses
			if (!trustedEntity.policyIncludesAddress(policy, from)) return false
			
			// consider policy if associated selector is the first one matching or policy is not excluded from 'relaxed' trustConfig.selectorMode
			//return entityIdx == 0 || policy.selectorMode !== 'strict'
			return entityIdx == 0 || policy.onRemedy !== 'skip'
		})
		
		if (!selectedPolicy) {
			alertMatchDetails('Sender address policy on selector '+ trustedEntity.selector +' violated', Utils.extractAddress(from))
			if (onViolation != 'trash') {
				if (trustedEntity.policyList.length == 1)
					onViolation = trustedEntity.policyList[0].onViolation
				onViolation = onViolation || trustedEntity.onViolation
			}
			
			return true  // no address match
		}
		
		try {
			// create auth methods from blueprint or policy's own definitions
			trustedEntity.setupPolicyAuthMethods(selectedPolicy)
		} catch (err) {
			alertError(err.message)
			return false
		}
		
		// prefer user-defined actions to default and choose harshest action
		if (selectedPolicy.onViolation && onViolation != 'trash')
			onViolation = selectedPolicy.onViolation
		if (trustedEntity.onViolation && onViolation != 'trash')
			onViolation = trustedEntity.onViolation
		
		// test the message against selected policy
		const violationResult = trustedEntity.testPolicyViolation(selectedPolicy, message)
		shouldProceedTests = violationResult.proceedTests
		
		if (!violationResult.violated && entityIdx > 0 && selectedPolicy.onRemedy === 'flag') {
			// consider policy if associated selector is the first one matching or policy is not excluded from 'relaxed' trustConfig.selectorMode
			alertMatchDetails('Redeeming previous violation prohibited')
			violationResult.onBorderline = selectedPolicy.onRemedy
		}
		
		// alert violation description
		if (violationResult.violated && violationResult.description)
			alertMatchDetails(violationResult.description)
		else if (violationResult.description)
			alertError(violationResult.description)
		
		// borderline case => no violation, though soft violation action ('flag')
		if (violationResult.onBorderline) {
			isBorderline = true
			onViolation = violationResult.onBorderline
			alertMatchDetails('Borderline case found on selector '+ trustedEntity.selector)
		}
		
		return violationResult.violated
	})
	return {violated: violated, isBorderline: isBorderline, shouldProceed: shouldProceedTests,
		onViolation: onViolation}
}

/** returns spam match (true) if self addressed email (from === receiver address) doesn't include account owner's full name */
function testSelfAddressedForFullName (accountEmail, message) {
	var from = message.getField('from')
	if (from == "") return true  // no sender provided
	if (from.includes(accountEmail)) {
		const res = !from.includes(message.mailbox.account.fullName)
		if (res) alertMatchDetails('Sender == receiver test', 'Self addressed without full name')
		return res
	}
	return false
}

/** returns spam match (true) if sender's name consists of only one word not included in whitelist and whitelist.shouldTest == true */
function testSenderForFullName (whitelist, message) {
	if (!whitelist.shouldTest) return false
	const from = message.getField('from')
	const addressIdx = from.indexOf("<")  // e.g. X Y <xy@abc.com>
	if (addressIdx <= 0) return false
	const name = from.substring(0, addressIdx).trim().replace(/"/g, '')
	if (name === "" || name.indexOf(" ") > 0) return false
	const res = !whitelist.list.includes(name)
	if (res) alertMatchDetails('Sender with full name test', 'Found only one word')
	return res
}

/** returns spam match (true) if at least one entry in blacklist matches */
function testHeaders (headerBlacklist, message) {
	if (!headerBlacklist) return false
	
	return headerBlacklist.some(function(item) {
		return testMessageField(item.name, item, message)
	})
}

/** tests for matches between message and similarity blacklist */
function testMessageFieldBySimilarity (field, similarityBlacklist, message) {
	if (!similarityBlacklist) return false
	
	const searchContent = message.getField(field),
		canonicalContent = Utils.canonicalize(searchContent)
	return similarityBlacklist.some(item => {
		if (!item._similarity) {
		  try {
			item._similarity = new Similarity(item.selector, item.similarityMode)
		  } catch (err) {  // catches configuration errors caused by the user
			alertError(error.message)
			return false
		  }
		}
		
		const hasSelectorMatched = item._similarity.hasMatch(canonicalContent)
		if (hasSelectorMatched)
			alertMatchDetails('Sender with similarity to selector', item.selector)
		return hasSelectorMatched
	})
}

/** tests for matches between message field and blacklist */
function testMessageField (field, blacklist, message) {
	const searchContent = message.getField(field)
	
	if (field === "source") {
		// determine boundary for multipart messages
		//const headers = message.allHeaders()
		var boundary = ''
	} else {  // i.e. from, subject
		if (searchContent.length == 0) return false
		
		// delete unicode cheat chars
		const normalizedContent = cheatChars.reduce(function(res, item) {
			return res.replace(new RegExp(item, 'g'), '')
		}, searchContent)
		
		return blacklist.list.some(function(item) {
			// skip empty strings created by accident
			if (item.length === 0) return false
			
			const res = normalizedContent.includes(item);  // true if match in blacklist
			if (res) alertMatchDetails('Field "'+ field +'"', item)
			return res
		})
	}

	// search message body from raw source
	var initSearchPos = 0
	const messageComponentsHandler = new MessageComponentsHandler(searchContent, initSearchPos, boundary)
	while (messageComponentsHandler.hasNextPart()) {
		// search for blacklist item within current message part
		var part = messageComponentsHandler.getNextPart();
		if (part === false)
			// message not searchable
			return false;
		
		// check for evil file name or file extensions
		if (part.fileName !== null) {
			if (fileExtensions.some(function(c) {
				  const res = part.fileName.indexOf(c) >= 0
				  if (res) alertMatchDetails('File extension', c)
				  return res
				})
			)
				return true
			continue
		}
		// check for evil charsets
		if (part.type !== null) {
			if (charsetBlacklist.some(function(c) {
				  const res = part.type.indexOf(c) >= 0
				  if (res) alertMatchDetails('Charset', c)
				  return res
				})
			)
				return true
		}
		
		var searchTarget = searchContent
		var searchPartStart = part.start

		if (part.encoding === "base64" || part.type.indexOf("html") >= 0
		  || part.encoding === "quoted-printable") {
			// choose decoded string as search target
			var decodedContent = part.decode(searchTarget)
			if (typeof decodedContent !== "undefined") {
				searchTarget = decodedContent
				searchPartStart = 0  // decoded text is unrelated to part positioning of original message!
			}
		}
		
		var searchPart = searchTarget.substring(searchPartStart, part.end)
		
		// check for cheating zero-width spaces once per message part
		if (messageComponentsHandler.isParsed === false && cheatChars.some(function(c) {
			  const idx = searchPart.indexOf(c, 1), res = idx > 0
			  if (res) {
			  	const unicode = 'U+'+ c.codePointAt(0).toString(16).toUpperCase()
				alertMatchDetails('Cheat char at idx '+ idx, unicode)
			  }
			  return res
			})
		)
			return true  // cheat char detected => spam mail
			  
		if (blacklist.list.some(function(item) {
			  const res = searchPart.indexOf(item) !== -1 && item.length > 0
			  if (res) alertMatchDetails('Text content', item)
			  return res
			})
		)
			return true  // match in blacklist
	}
	return false  // no matches in blacklist
}

// helper functions
/** includes all properties and actions required for message part handling */
function MessagePart (start, end, type, encoding) {
	this.start = start			// start position of message part content
	this.end = end				// end position of message part content
	this.type = type.toLowerCase() // content-type of message part
	this.fileName = null		// set if part contains a binary file
	this.encoding = encoding.toLowerCase() // content-transfer-encoding of message part
	this.multiBoundary = ''	// boundary at the very end of the part (multipart/...)
	this.decoded = null		// decoded message part content if raw data is b64 encoded or html entities might be included
}
/** sets end position of message part only if not already set */
MessagePart.prototype.setEnd = function(e) {
	if (this.end === 0) this.end = e
}
	
/** true, when end position is set */
MessagePart.prototype.hasEnd = function() {
	return this.end !== 0
}
	
/** sets and returns decoded message part content if raw data is b64/qp encoded; normalize umlauts and decode &#ddd; chars in html*/
MessagePart.prototype.decode = function(rawMsg) {
	if (this.decoded !== null) return this.decoded
		
	// extract charset from content-type
	var charset = "", charsetIdx = this.type.indexOf("charset=")
	if (charsetIdx > 0) {
		charset = this.type.substr(charsetIdx+8).trim()
		if (charset[0] === '"')  // omit leading/ trailing quote marks
			charset = charset.substr(1, charset.length-2).trim()
	}
	
	var inputStr = rawMsg.substring(this.start, this.end)  // encoded message part
	
	// handle transfer encoding
	if (this.encoding === "base64") {
		const firstLine = inputStr.substring(0, 80)
		if (firstLine && firstLine.indexOf(" ") >= 0) {
			this.decoded = inputStr
			console.log("not a real base64 encoding")
		} else {
			var wsFreeStr = inputStr.replace(/\s+/g, "")
			if (wsFreeStr.startsWith("77u/")) // skip binary indicator before decode
				wsFreeStr = wsFreeStr.substring(4)
			this.decoded = b64DecodeUnicode(wsFreeStr, charset)
		}
	}
	else if (this.encoding === "quoted-printable") {
		this.decoded = qpDecodeUnicode(inputStr, charset)
	}
	
	if (this.type.indexOf("html") >= 0) {
		if (this.decoded == null) this.decoded = inputStr
		this.decoded = htmlDecodeUnicode(this.decoded)
	}
	return this.decoded
}

/** returns content of next specified header as well as start and end position of the header line relative to searchContent */
function getLocalHeader (headerName, searchContent, startPos) {
	headerName += ":"
	// find first occurence case-insensitive, e.g., "\nContent-Type:" or "\ncontent-type:"
	var headerStartPos = searchContent.substring(startPos)
		.search(new RegExp("\\n"+ headerName, "i"))
	if (headerStartPos === -1) return false  // header not found
	
	// make index from substring() relative to searchContent and skip leading "\n" by +1
	headerStartPos += startPos + 1
	
	var headerEndPos = searchContent.indexOf("\n", headerStartPos + headerName.length)
	var line = searchContent.substring(headerStartPos + headerName.length, headerEndPos).trim()
	var lineEndPos = headerEndPos
		
	while (line[line.length-1] === ";") {
		// another parameter in next line
		headerEndPos = searchContent.indexOf("\n", headerEndPos+1)
		// skip empty lines
		if (headerEndPos-1 === lineEndPos) continue
		
		line = searchContent.substring(lineEndPos+1, headerEndPos).trim()
		lineEndPos = headerEndPos
	}
	
	return {headerContent: searchContent.substring(headerStartPos + headerName.length, headerEndPos).trim(),
		lineStartPos: headerStartPos,
		lineEndPos: headerEndPos}
}

/** Parses message body and builds list of message parts */
function MessageComponentsHandler (rawMessage, contentStartPos, boundary) {
	this.rawMessage = rawMessage
	this.contentStartPos = contentStartPos
	this.searchPos = contentStartPos
	this.boundary = boundary
	this.boundaryList = boundary ? [boundary] : []
	this.partsList = []
	this.partIdx = 0  // INTERNAL part index
	this.isParsed = false
}
MessageComponentsHandler.prototype.hasNextPart = function() {
	return (this.partsList.length > this.partIdx) || !this.isParsed
}
	
MessageComponentsHandler.prototype.resetIterator = function() {
	this.partIdx = 0
}
MessageComponentsHandler.prototype.getNextPart = function() {
	if (!this.hasNextPart())
		// index out of bounds
		return false

	if (this.isParsed === true)
		// get message part set during iteration for previous search item
		return this.partsList[this.partIdx++]

	// search for further content headers as long as list of parts is incomplete
	var contentTransEncoding = getLocalHeader("Content-Transfer-Encoding", this.rawMessage, this.searchPos)
	var contentType = getLocalHeader("Content-Type", this.rawMessage, this.searchPos)

	if ((contentTransEncoding || contentType) == false) {
		// no more relevant search content left
		this.isParsed = true
		this.resetIterator()
		return false
	}
	
	// define new additional message part
	if (!contentTransEncoding || !contentType) {
		var beyondHeadersPos = contentType.lineEndPos
		var dummy = {headerContent: "", lineStartPos: undefined, lineEndPos: undefined}
		if (beyondHeadersPos == undefined) {
			contentType = dummy
			beyondHeadersPos = contentTransEncoding.lineEndPos
		} else
			contentTransEncoding = dummy
	} else {
		var minHeader = Math.min(contentType.lineEndPos, contentTransEncoding.lineEndPos)
		var corruptedHeader = this.rawMessage.indexOf("\n\n", minHeader)
		if (contentType.lineEndPos > corruptedHeader || contentTransEncoding.lineEndPos > corruptedHeader) {
			// one of the two headers is missing
			var beyondHeadersPos = contentType.lineEndPos
			contentTransEncoding.headerContent = ""  // header for wrong part
		} else
			var beyondHeadersPos = Math.max(contentType.lineEndPos, contentTransEncoding.lineEndPos)  // points to first \n after headers
	}
	
	var freeLinePos = this.rawMessage.indexOf("\n\n", beyondHeadersPos)
	var part = new MessagePart(
		freeLinePos+2,
		0,
		contentType.headerContent,
		contentTransEncoding.headerContent
	)
	
	var innerBoundary = MessageComponentsHandler.getBoundary(contentType.headerContent)
	if (innerBoundary !== "") {
		part.multiBoundary = innerBoundary
		this.boundaryList.push(innerBoundary)
		part.start--
	}
	
	var searchable = this.determineSearchableContent(part)
	if (searchable === -1) {
		// only, e.g., binary base64 content left
		this.isParsed = true
		return false
	}
	if (searchable === -2)
		// parse remaining message content
		return this.getNextPart()
	
	// determine end of part
	this.determinePartEnd(part)
			
	this.partsList.push(part)
	this.searchPos = part.end + 1  // proceed with next message part
	this.partIdx++
	return part
}
	
MessageComponentsHandler.prototype.determineSearchableContent = function(part) {
	// binary data only searchable by filename and file extensions
	if (part.type.includes("application/")) {
		var fileNameStart = part.type.indexOf("name=", 12)
		var fileNameEnd = part.type.indexOf("\n", fileNameStart+5)
		if (fileNameEnd < 0) fileNameEnd = part.type.length
		part.fileName = part.type.substring(fileNameStart, fileNameEnd)
		return true
	}
	
	// multipart component treated as empty message part
	if (part.type.includes("multipart/")) {
		/*var firstChildPos = this.rawMessage.indexOf(part.multiBoundary, part.start);
		part.setEnd(firstChildPos + part.multiBoundary.length);*/
		return true
	}
	
	if (part.encoding !== "base64" || part.type.includes("text/")
		  || part.type.includes("message/"))
		return true
	
	// only accessed once per base64 part, because messagePartsList excludes them
	if (this.boundaryList.length === 0) {
		part.setEnd(this.rawMessage.length-1)
		return -1  // whole message is non-text => can't search
	}
	
	var pos = -1, i = this.boundaryList.length-1
	for (i; i>-1; i--) {
		var pos = this.rawMessage.indexOf(this.boundaryList[i], part.start)
		if (pos > -1) break
	}
	this.searchPos = pos  // skip message part
	
	// remove last boundary from list if not used anymore
	if (i < this.boundaryList.length-1)
		this.boundaryList.pop()
	
	this.searchPos += this.boundaryList[i].length
	return -2	// don't append to messagePartsList
}
	
MessageComponentsHandler.prototype.determinePartEnd = function(part) {
	// determine search limit
	if (this.boundaryList.length === 0) {
		// message consists of 1 part
		part.setEnd(this.rawMessage.length-1)
		return
	}
	
	// determine end position for search within current part
	if (part.end < 1) {
		var searchPartEnd = -1, i = this.boundaryList.length-1
		for (i; i>-1; i--) {
			var searchPartEnd = this.rawMessage.indexOf(this.boundaryList[i], part.start)
			if (searchPartEnd > -1) break
		}
		// remove last boundary from list if not used anymore
		if (i < this.boundaryList.length-1)
			this.boundaryList.pop()
	} else
		var searchPartEnd = part.end
	
	if (searchPartEnd-- === -1)
		searchPartEnd = this.rawMessage.length-1  // if missing final boundary
		
	// hardening against inconsistent boundaries
	var lastNewLinePos = this.rawMessage.lastIndexOf("\n", searchPartEnd)
	
	part.setEnd(lastNewLinePos)
}


/** extract boundary from given content-type header string if possible*/
MessageComponentsHandler.getBoundary = function(str){
	var boundaryPos = str.indexOf("boundary="), boundary = ""
	if (boundaryPos !== -1) {
		boundary = str.substr(boundaryPos+9).trim()
		if (boundary[0] == '"')
			boundary = boundary.substr(1, boundary.length-2)  // omit enclosing quotes
		// omit leading and trailing sequences of '-'
		boundary = boundary.replace(/^-+|-+$/g, '')
	}
	return boundary
}


/** html special entities decoding function */
function htmlDecodeUnicode (rawStr, charset = "") {
	var idx = 0, res = ''
	var htmlEntities = {"&auml;":"ä", "&Auml;":"Ä", "&ouml;":"ö", "&Öuml;":"Ö", "&uuml;":"ü", "&Uuml;":"Ü", "&szlig;":"ß", "&zwnj;":"", "<\/?[Ss][^>]*>":"", "<\/?(?:font|FONT)[^>]*>":"" /*, "&#x200[cC];":"","&#228;":"ä", "&#196;":"Ä", "&#246;":"ö", "&#214;":"Ö", "&#252;":"ü", "&#220;":"Ü", "&#223;":"ß", "&#8364;":"€"*/}
	// code points of, e.g., &#8204;
	var customCodePointRplc = {"8204":"", "65279":"", "x200c":"", "x200C":""}
	
	var regexMap = {}
	for (var str in htmlEntities) {
		regexMap[str] = new RegExp(str, "g")
	}
	
	var delimiter = null, maxDelimiterOffset = 0
	
	while (idx < rawStr.length) {
		if (rawStr[idx] === '&') {
			// special html entities
			delimiter = ';'
			maxDelimiterOffset = 7
		}
		else if (rawStr[idx] === '<') {
			// html tags
			delimiter = '>'
			maxDelimiterOffset = 30
		}
		else {
			res += rawStr[idx++]
			continue
		}
		
		// determine offset of end delimiter
		var delimiterFound = false
		for (var delimiterOffset=2; delimiterOffset <= maxDelimiterOffset; delimiterOffset++) {
			if (idx + delimiterOffset >= rawStr.length) break
			
			if (rawStr[idx + delimiterOffset] === delimiter) {
				delimiterFound = true
				break
			}
		}
		if (delimiterFound) {
			var entity = ''
			if (delimiter === ';' && rawStr[idx+1] === '#') {
				// decode all special decimal entities to unicode chars
				entity = rawStr.substr(idx+2, delimiterOffset-2)
				if (customCodePointRplc[entity] !== undefined)
					entity = customCodePointRplc[entity]
				else
					entity = String.fromCodePoint(entity | 0)
			}
			else {
				entity = rawStr.substr(idx, delimiterOffset+1)
				for (var str in htmlEntities) {
					// replace with unicode char/ empty string if regex matches htmlEntities
					entity = entity.replace(regexMap[str], htmlEntities[str])
				}
			}
			res += entity
			idx += delimiterOffset + 1
		}
		else
			res += rawStr[idx++]  // no special entity
	}
	return res
}

/** base64 decoding function */
function b64DecodeUnicode (rawStr, charset = "") {
	var arr = base64Handler.decode(rawStr)
	if (charset === "iso-8859-1")
		return decodeBinaryAsIso88591Str(arr)
	return decodeBinaryAsUtf8Str(arr)
}

/** QuotedPrintable decoding function */
function qpDecodeUnicode (rawStr, charset = "") {
	var res = QuotedPrintableHandler.decode(rawStr)
	//mail.displayDialog(res.arr.toString());
	if (charset === "iso-8859-1")
		return decodeBinaryAsIso88591Str(res.arr, res.length)
	return decodeBinaryAsUtf8Str(res.arr, res.length)
}

/** takes UTF-8 byte array and converts to unicode string */
function decodeBinaryAsUtf8Str (arr, len = 0) {
	var res = ''
	var idx = 0, arrLength = len > 0 ? len : arr.length
		
	/* 1 byte char 0x00 0xxxxxxx; 0x80 10000000 bitmask
	   2 byte char 0xC0 110xxxxx; 0xE0 11100000 bitmask
	   3 byte char 0xE0 1110xxxx; 0xF0 11110000 bitmask
	   4 byte char 0xF0 11110xxx; 0xF8 11111000 bitmask
	   following byte 0x80 10xxxxxx; 0xC0 11000000 bitmask
	*/
	while (idx < arrLength) {
		if ((arr[idx] & 0x80) === 0x00) {	// 1 byte char
			res += String.fromCharCode(arr[idx++])
		}
		else if ((arr[idx] & 0xE0) === 0xC0 && (arr[idx+1] & 0xC0) === 0x80) {
			// 2 bytes char
			res += String.fromCharCode(((arr[idx++]&0x1F) << 6) | (arr[idx++]&0x3F))
		}
		else if ((arr[idx] & 0xF0) === 0xE0 && (arr[idx+1] & 0xC0) === 0x80
				 && (arr[idx+2] & 0xC0) == 0x80) {
			// 3 bytes char
			var code = ((arr[idx++]&0x0F) << 12) | ((arr[idx++]&0x3F) << 6)
			  | (arr[idx++]&0x3F)
			try {
				res += String.fromCodePoint(code)
			} catch (e){
				//console.log('decoded part: '+res)
				//console.log('error 3 bytes: '+e + ', '+ code.toString(16))
				res += code == 0xEFBBBF ? '\uFEFF' : '\uFFFD'
			}
		}
		else if ((arr[idx] & 0xF8) === 0xF0 && (arr[idx+1] & 0xC0) === 0x80
			 && (arr[idx+2] & 0xC0) === 0x80 && (arr[idx+3] & 0xC0) === 0x80) {
			 // 4 bytes char
			var code = ((arr[idx++]&0x07) << 18) | ((arr[idx++]&0x3F) << 12) | ((arr[idx++]&0x3F) << 6)
			 	| (arr[idx++]&0x3F)
			try {
				res += String.fromCodePoint(code)
			} catch (e) {
			  	//console.log('decoded part: '+res)
				//console.log('error 4 bytes: '+e + ', '+ code.toString(16))
				res += code == 0xEFBBBF ? '\uFEFF' : '\uFFFD'
			}
		}
		else {
			res += '\uFFFD'
			idx++
		}
	}
	//console.log('decoded unicode: '+res)
	return res
}

/** takes ISO 8859-1 (Latin-1) byte array and converts to unicode string */
function decodeBinaryAsIso88591Str (arr, len = 0) {
	var res = ''
	var idx = 0, arrLength = len > 0 ? len : arr.length
	
	for (idx; idx<arrLength; idx++) {
		res += String.fromCharCode(arr[idx])
	}
	return res
}

// based on base64-js lib at https://github.com/beatgammit/base64-js
const base64Handler = (function () {
	var lookup = []
	var revLookup = []
	var Arr = typeof Uint8Array !== 'undefined' ? Uint8Array : Array

	var code = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
	for (var i = 0, len = code.length; i < len; ++i) {
  		lookup[i] = code[i]
  		revLookup[code.charCodeAt(i)] = i
	}

	revLookup['-'.charCodeAt(0)] = 62
	revLookup['_'.charCodeAt(0)] = 63

	function placeHoldersCount (b64) {
  		var len = b64.length
  		if (len % 4 > 0 && (len+2) % 4 > 0) {
			console.log("error: "+len+' '+b64.slice(-50));
    	 	throw new Error('Invalid string. Length '+len+' must be a multiple of 4')
  		}
  		return b64[len - 2] === '=' ? 2 : b64[len - 1] === '=' ? 1 : 0
	}

	function byteLength (b64) {
  		// base64 is 4/3 + up to two characters of the original data
  		return (b64.length * 3 / 4) - placeHoldersCount(b64)
	}

	return {decode: function (b64) {
		var i, j, l, tmp, placeHolders, arr
		var len = b64.length
		try {
			placeHolders = placeHoldersCount(b64)
		} catch (err) {
			alertError("B64 decode error: " + err.message);
			return null
		}
		arr = new Arr((len * 3 / 4) - placeHolders)

		// if there are placeholders, only get up to the last complete 4 chars
		l = placeHolders > 0 ? len - 4 : len
		var L = 0

		for (i = 0, j = 0; i < l; i += 4, j += 3) {
			tmp = (revLookup[b64.charCodeAt(i)] << 18) | (revLookup[b64.charCodeAt(i + 1)] << 12) | (revLookup[b64.charCodeAt(i + 2)] << 6) | revLookup[b64.charCodeAt(i + 3)]
			arr[L++] = (tmp >> 16) & 0xFF
			arr[L++] = (tmp >> 8) & 0xFF
			arr[L++] = tmp & 0xFF
		}

		if (placeHolders === 2) {
			tmp = (revLookup[b64.charCodeAt(i)] << 2) | (revLookup[b64.charCodeAt(i + 1)] >> 4)
			arr[L++] = tmp & 0xFF
		} else if (placeHolders === 1) {
			tmp = (revLookup[b64.charCodeAt(i)] << 10) | (revLookup[b64.charCodeAt(i + 1)] << 4) | (revLookup[b64.charCodeAt(i + 2)] >> 2)
			arr[L++] = (tmp >> 8) & 0xFF
			arr[L++] = tmp & 0xFF
		}
		return arr}
	}
})()

// based on https://github.com/ronomon/quoted-printable/blob/master/index.js and https://github.com/mathiasbynens/quoted-printable/blob/master/src/quoted-printable.js
const QuotedPrintableHandler = (function () {
	var Arr = typeof Uint8Array !== 'undefined' ? Uint8Array : Array
	var decodeTable = (function(){
		var alphabet = '0123456789ABCDEFabcdef'
  		var table = new Arr(256)
  		for (var index = 0, length = alphabet.length; index < length; index++) {
    		var char = alphabet[index];
    	// Add 1 to all values so that we can detect hex digits with the same table.
    	// Subtract 1 when needed to get to the integer value of the hex digit.
    		table[char.charCodeAt(0)] = parseInt(char, 16) + 1;
  		}
  		return table
  	})()
	
	return {decode: function (src, useQEncoding = false) {
		var getLineBreakSize = function(){
			if (byteSrc[sIdx] === 13 && sIdx+1 < len && byteSrc[sIdx+1] === 10)
				return 2
			if (byteSrc[sIdx] === 13 || byteSrc[sIdx] === 10)
				return 1
			return 0
		}
		var len = src.length, byteSrc = new Arr(len), res = new Arr(len)
		
		// convert char to binary
		for (var i=0; i<len; i++)
			byteSrc[i] = src[i].charCodeAt(0)
		
		var sIdx = 0, resIdx = 0
		while (sIdx < len) {
			if ((byteSrc[sIdx]) === 61/* '=' */ && sIdx+2 < len
			  && decodeTable[byteSrc[sIdx+1]]
			  && decodeTable[byteSrc[sIdx+2]]) {
				res[resIdx++] = ((decodeTable[byteSrc[sIdx+1]] - 1) << 4)
				 + ((decodeTable[byteSrc[sIdx+2]] - 1))
				sIdx += 3
			}
			else if (byteSrc[sIdx] === 13/* CR */ || byteSrc[sIdx] === 10/* LF */) {
				// overwrite trailing whitespaces TAB/SPACE
				var rewindIdx = sIdx
				while (resIdx > 0 && rewindIdx > 0
				  && (byteSrc[rewindIdx-1] === 9 || byteSrc[rewindIdx-1] === 32)) {
					resIdx--
					rewindIdx--
				}
				if (resIdx > 0 && rewindIdx > 0 && byteSrc[rewindIdx-1] === 61) {
					// soft line break with '=' as last non-whitespace => transport encoding
					resIdx--
					sIdx += getLineBreakSize()
				}
				else {
					// add line break CR and/or LF
					for (var i = getLineBreakSize(); i>0; i--)
						res[resIdx++] = byteSrc[sIdx++]
				}
			}
			else if (useQEncoding === true && byteSrc[sIdx] === 95) {
				// replace '_' with ' '
				res[resIdx++] = 32
				sIdx++
			}
			else {
				res[resIdx++] = byteSrc[sIdx++]
			}
		}
		
		// remove trailing whitespace padding
		var rewindIdx = sIdx
		while (resIdx > 0 && rewindIdx > 0
		  && (byteSrc[rewindIdx-1] === 9 || byteSrc[rewindIdx-1] === 32)) {
			resIdx--
			rewindIdx--
		}
		
		return {arr: res, length: resIdx+1}}
	}
})()


/** Trust list item providing selectors, similarity and policies; JSON objects retrieved from rules config file are converted to this type */
function TrustedEntity() {
	this._similarity = null
	/*this._canonicalSelectorList = null
	this._simMode = 'canonical'
	this._simThreshold = 0*/
	this._policyBlueprints = null
}
/** Checks if selector matches 'From' header w.r.t. pre-configured similarity mode */
TrustedEntity.prototype.selectorHasMatched = function(from) {
	const hasSelectorMatched = this._similarity.hasMatch(from, this.shouldAlertSimilarity)
	return hasSelectorMatched
}
/** Setup internal Similarity object w.r.t. hierarchical config definitions */
TrustedEntity.prototype.initSimilarityTest = function(trustConfig) {
	const similarityMode = this.similarityMode || trustConfig.similarityMode
	this.shouldAlertSimilarity = this.shouldAlertSimilarity === true
	
	this._similarity = new Similarity(this.selector, similarityMode)
}
/** Checks if policy is responsible for the address from given 'From' header */
TrustedEntity.prototype.policyIncludesAddress = function(policy, from) {
	var addressList = policy._parsedAddressList  // use already parsed policy address list
	if (!addressList) {
		addressList = Utils.listFromStr(policy.addresses)
		policy._parsedAddressList = addressList
	}
	
	const hasMatched  = addressList.some((address) => {
		if (address[0] == '*') {  // wildcard at start idx
			address = address.substring(1)
			return from.endsWith(address +'>') || from.endsWith(address)
		}
		return from == address || from.endsWith('<'+ address +'>')
	})
	return hasMatched
}
/** Extracts auth methods from blueprint definitions and overwrite with policy's own defs */
TrustedEntity.prototype.setupPolicyAuthMethods = function(policy) {
	if (policy._didAuthSetup) return  // only setup once
	
	// try to find desired blueprint object
	const blueprintObj = policy.blueprint && Utils.isObjectKeyValid(policy.blueprint)
		&& this._policyBlueprints ? this._policyBlueprints[policy.blueprint] : null
	if (policy.blueprint && !blueprintObj) {
		throw new Error('Policy blueprint '+ policy.blueprint +' not found')
	}
	
	var issuerList = this._authResultsIssuerList
	
	if (blueprintObj) {  // setup policy auth blueprints
	  if (blueprintObj.dkim && !blueprintObj._dkimHandler)
		blueprintObj._dkimHandler = new DKIMHandler(Utils.listFromStr(blueprintObj.dkim))
		
	  if (blueprintObj.spf && !blueprintObj._spfHandler)
		blueprintObj._spfHandler = new SPFHandler(blueprintObj.spf)
		
	  if (blueprintObj.dmarc && !blueprintObj._dmarcHandler)
		blueprintObj._dmarcHandler = new DMARCHandler(blueprintObj.dmarc)
		
	  if (blueprintObj.authResults && !blueprintObj._authResultsHandler) {
	  	if (issuerList.length == 0)
			issuerList = Utils.listFromStr(blueprintObj.authResults.issuers || null)
		const protocolList = Utils.listFromStr(blueprintObj.authResults.methods),
			borderlineMode = blueprintObj.authResults.borderlineMode || null
		blueprintObj._authResultsHandler = new AuthenticationResultsHandler(protocolList, issuerList, borderlineMode)
	  }
	  
	  if (blueprintObj.headerList && !blueprintObj._headerListHandler)
		blueprintObj._headerListHandler = new HeaderMatchHandler(blueprintObj.headerList)
	}
	
	// setup policy auth criteria
	policy._dkimHandler = policy.dkim ? new DKIMHandler(Utils.listFromStr(policy.dkim))
	  : blueprintObj ? blueprintObj._dkimHandler : null
	
	policy._spfHandler = policy.spf ? new SPFHandler(policy.spf)
	  : blueprintObj ? blueprintObj._spfHandler : null
	
	policy._dmarcHandler = policy.dmarc ? new DMARCHandler(policy.dmarc)
	  : blueprintObj ? blueprintObj._dmarcHandler : null
	
	if (policy.authResults) {  // overwrite complete blueprintObj.authResults
		if (this._authResultsIssuerList.length == 0)
			issuerList = Utils.listFromStr(policy.authResults.issuers || null)
		const protocolList = Utils.listFromStr(policy.authResults.methods),
			borderlineMode = policy.authResults.borderlineMode || null
		policy._authResultsHandler = new AuthenticationResultsHandler(protocolList, issuerList, borderlineMode)
	} else policy._authResultsHandler = blueprintObj ? blueprintObj._authResultsHandler : null
	
	policy._headerListHandler = policy.headerList ? new HeaderMatchHandler(policy.headerList)
	  : blueprintObj ? blueprintObj._headerListHandler : null
	
	if (policy.proceedTests === undefined)
		policy.proceedTests = blueprintObj ? blueprintObj.proceedTests : false
	if (policy.onViolation === undefined)
		policy.onViolation = blueprintObj ? blueprintObj.onViolation : 'trash'
	
	policy._didAuthSetup = true
}
/** Tests message against all auth methods required by policy and return violation results including borderline case status and error description */
TrustedEntity.prototype.testPolicyViolation = function(policy, message) {
	const res = {violated: true, proceedTests: false, onBorderline: null, description: null}
	
	// test DKIM header
	if (policy._dkimHandler) {
		const dkimHandler = policy._dkimHandler
		if (!message.dkimHeaders) DKIMHandler.parseMsgHeader(message)
		
		if (!dkimHandler.verify(message)) {
			res.description = 'DKIM policy on selector '+ this.selector +' violated for address '+ Utils.extractAddress(message.getField2('from'))
			return res
		}
		//alertInfo('dkim')
	}
	  
	// test SPF header
	if (policy._spfHandler) {
		const spfHandler = policy._spfHandler
		if (!message.spfHeader) SPFHandler.parseMsgHeader(message)
		
		if (!spfHandler.verify(message)) {
			res.description = 'SPF policy on selector '+ this.selector +' violated for Return-Path '+ message.getField2('return-path')
			return res
		}
		
		// borderline result
		if (spfHandler.borderlineCase && spfHandler.borderlineCase.isBorderline) {
			res.onBorderline = spfHandler.borderlineCase.onBorderline
		}
		//alertInfo('spf')
	}
	  
	// test DMARC
	if (policy._dmarcHandler) {
	  	const dmarcHandler = policy._dmarcHandler
		DMARCHandler.parseMsgHeader(message)
		
		if (!dmarcHandler.verify(message)) {
			res.description = 'DMARC policy on selector '+ this.selector
				+' violated for sender address '
				+ Utils.extractAddress(message.getField2('from'))
			return res
		}
		
		// borderline result
		if (dmarcHandler.borderlineCase && dmarcHandler.borderlineCase.isBorderline) {
			res.onBorderline = dmarcHandler.borderlineCase.onBorderline
		}
		//alertInfo('dmarc')
	}
	  
	// test Authentication-Results header
	if (policy._authResultsHandler) {
		let authResHandler = policy._authResultsHandler
		if (!message.authResHeaders) AuthenticationResultsHandler.parseMsgHeader(message)
		
		if (!authResHandler.verify(message)) {
			res.description = 'Authentication-Results policy on selector '+ this.selector +' violated for policy '+ policy.addresses
			return res
		}
		
		// borderline result
		if (authResHandler.borderlineCase && authResHandler.borderlineCase.isBorderline) {
			res.onBorderline = authResHandler.borderlineCase.onBorderline
		}
		//alertInfo('auth results')
	}
	  
	// test further specified headers
	if (policy._headerListHandler) {
	  	const headerHandler = policy._headerListHandler
		
		if (!Array.isArray(headerHandler.headerQueryList)) {
			res.description = 'Wrong typed headerList in policy for selector '+ this.selector
			res.violated = false
			return res
		}
		if (!headerHandler.verify(message)) {
			res.description = 'Header match policy on selector '+ this.selector +' violated'
			return res
		}
		//alertInfo('header list')
	}
	  
	// no violation => policy fulfilled
	res.proceedTests = policy.proceedTests === true
	res.violated = false
	return res
}
/** Checks if internal similarity object has been setup */
TrustedEntity.prototype.isSimilaritySetup = function() {
	return this._similarity instanceof Similarity
}
/** Converts JSON object from rules config file to TrustetEntity typed object */
TrustedEntity.applyRuntimeProperties = function(trustedEntity, trustConfig) {
	Object.setPrototypeOf(trustedEntity, TrustedEntity.prototype)
	
	// parse and store top-level authserv-id list
	trustedEntity._authResultsIssuerList = Utils.listFromStr(trustConfig.authResultsIssuers
		|| null)
	// store reference to mailbox's policy blueprints object
	trustedEntity._policyBlueprints = trustConfig.policyBlueprints
	
	trustedEntity.initSimilarityTest(trustConfig)
}


/** Algorithms to determine similarity for given mode (canonical, dl or jw + threshold) between needle and haystack strings */
function Similarity(selectorList, modeStr) {
	if (!selectorList || selectorList.length === 0)
		throw new Error('Unknown selector in trustList')
	
	// create canonicalized selector list
	// reduces number of necessary canonicalize() calls through lazy evaluation
	if (Array.isArray(selectorList)) {
		this.canonicalSelectorList = selectorList.map(selector => {
		  return Utils.canonicalize(selector)
		})
	} else
		this.canonicalSelectorList = [Utils.canonicalize(selectorList)]
	
	// setup similarity mode
	if (!modeStr || modeStr === 'canonical') {
		this.mode = 'canonical'
		this.threshold = 0
	} else {
		[this.mode, this.threshold] = modeStr.split(':', 2)
		if (this.mode === 'dl') {
			this.threshold = Number.parseInt(this.threshold)
			if (!this.threshold || this.threshold < 0)
				throw new Error('Invalid dl threshold for selector '+ selectorList)
		} else if (this.mode === 'jw') {
			this.threshold = Number.parseFloat(this.threshold)
			if (!this.threshold || this.threshold < 0 || this.threshold > 1)
				throw new Error('Invalid jw threshold for selector '+ selectorList)
		} else throw new Error('Unknown similarity mode for selector '+ selectorList)
	}
}
/** Returns similarity check result as boolean w.r.t. threshold */
Similarity.prototype.hasMatch = function(haystack, shouldAlertSimilarity = false) {
	if (this.mode == 'jw') {
	  return this.canonicalSelectorList.some(selector => {
		const score = Similarity.getFreeShiftJaroWinklerSim(selector, haystack)
		if (shouldAlertSimilarity)
			alertInfo(`selector: ${selector}\nfrom: ${haystack}\njw-score: ${score}; threshold: ${this.threshold}`)
		return score >= this.threshold
	  })
	} else if (this.mode == 'dl') {
	  return this.canonicalSelectorList.some(selector => {
		const dist = Similarity.getDamerauLevenshtein(selector, haystack)
		if (shouldAlertSimilarity)
			alertInfo(`selector: ${selector}\nfrom: ${haystack}\ndl-distance: ${dist}; threshold: ${this.threshold}`)
		return dist <= this.threshold
	  })
	} else {
		// default: canonical mode
	  return this.canonicalSelectorList.some(selector => {
	    const res = haystack.includes(selector)
		if (shouldAlertSimilarity)
			alertInfo(`selector: ${selector}\nfrom: ${haystack}`)
		return res
	  })
	}
}
/** Calculates enhanced Jaro-Winkler similarity at given startIdx of haystack */
Similarity.getJaroWinklerSim = function(needle, haystack, startIdx) {
	if (needle.length == 0 || haystack.length == 0) return 0
	
	// use needle.length for maxDistance as haystack is typically much longer
	const maxDistance = Math.min(Math.max((needle.length >> 1) - 1, 0), 3),
		consumedFlags = new Uint8Array(haystack.length)
	
	var matchCount = 0, transpositionCount = 0, gapCount = 0,
		prevMatchIdx = -1, expectedIdx = startIdx, highestExpectedIdx = expectedIdx
	for (let i=0; i < needle.length; i++) {
		const needleChar = needle[i]  // the current char searched for in haystack
		// define range of search window
		const minIdx = Math.max(expectedIdx - maxDistance, 0),
			maxIdx = Math.min(expectedIdx + maxDistance, haystack.length - 1)
		let matchIdx = -1
		// forward search
		for (let currIdx = expectedIdx+1; currIdx <= maxIdx; currIdx++) {
			if (needle[i] != haystack[currIdx] || consumedFlags[currIdx] == 1) continue
			
			matchIdx = currIdx
			break
		}
		// backward search
		for (let currIdx = expectedIdx; minIdx <= currIdx; currIdx--) {
			if (needle[i] != haystack[currIdx] || consumedFlags[currIdx] == 1) continue
			
			if (matchIdx >= 0) {
				// update to smaller distance idx
				if (expectedIdx - currIdx < matchIdx - expectedIdx) matchIdx = currIdx
				break
			}
			matchIdx = currIdx
			break
		}
		
		if (matchIdx >= 0) {
			matchCount++
			consumedFlags[matchIdx] = 1
			if (prevMatchIdx > matchIdx) {  // chars in wrong order
				transpositionCount++
			} else {
				expectedIdx = matchIdx + 1  // monotonic increment of expectedIdx
			}
			prevMatchIdx = matchIdx
			//expectedIdx = matchIdx + 1
		} else {  // needle char not found => gap
			// not incrementing expectedIdx avoids longer gaps in haystack
			//expectedIdx++
		}
		if (expectedIdx > highestExpectedIdx) highestExpectedIdx = expectedIdx
	}
	if (matchCount == 0) return 0
	
	const consumedLength = consumedFlags.lastIndexOf(1) - startIdx + 1,
		expectedLength = highestExpectedIdx - startIdx,
		needleMatchScore = matchCount / needle.length,
		haystackMatchScore = matchCount / Math.max(expectedLength, needle.length),
		transpositionScore = (matchCount - transpositionCount) / matchCount
	
	// Jaro similarity
	var similarity = (needleMatchScore + haystackMatchScore + transpositionScore) / 3
	
	// add prefix bonus
	var prefixLen = 0
	for (let i=0; i<4; i++) {
		if (needle[i] != haystack[startIdx + i]) break
		prefixLen++
	}
	similarity += prefixLen * 0.1 * (1 - similarity)
	
	// subtract mismatch penalty
	const mismatchCount = needle.length - matchCount
	if (mismatchCount > 1) {
		//similarity -= 0.5 * (mismatchCount-1)/(needle.length) * (similarity)
		similarity -= (Math.pow(0.8, -(needle.length/5 - 0.5)) - 0.6) * (mismatchCount-1)/needle.length * similarity
		similarity = Math.max(similarity, 0)
	}
	return similarity
}
/** Calculates enhanced Jaro-Winkler similarity at all haystack positions matching one of the first two needle chars */
Similarity.getFreeShiftJaroWinklerSim = function(needle, haystack) {
	const first = needle[0], second = needle[1]
	// always calculate score at beginning of haystack
	var score = Similarity.getJaroWinklerSim(needle, haystack, haystack.length > 2 ? 0 : 0)
	for (let i=1; i<haystack.length; i++) {
		// only calculate score for positions in haystack that match first needle char
		// checking the second needle char compensates absence of first char
		if (haystack[i] == first || haystack[i] == second) {
			let newScore = Similarity.getJaroWinklerSim(needle, haystack, i)
			if (score < newScore) score = newScore
			if (score == 1) break  // max score possible
		}
	}
	
	// neither first nor second needle char matched => force calculation at haystack index 0 
	//if (score == 0) score = Similarity.getJaroWinklerSim(needle, haystack, 0)
	
	return score
}
/** Calculates Damerau-Levenshtein distance with free leading and trailing string portions */
Similarity.getDamerauLevenshtein = function(needle, haystack) {
	var prevPrevRow = new Uint8Array(haystack.length + 1),
		prevRow = new Uint8Array(haystack.length + 1),
		currRow = new Uint8Array(haystack.length + 1)
	// init prevRow items to 0 for free leading/trailing gaps; Uint8Array does so per default
	
	for (let i=0; i < needle.length; i++) {
		currRow[0] = i + 1  // costs of deletions to reach empty haystack
		
		for (let j=0; j < haystack.length; j++) {
			const delCost = prevRow[j + 1] + 1,
				  insCost = currRow[j] + 1,
				  subCost = needle[i] == haystack[j] ? prevRow[j] : prevRow[j] + 1
			const cost = Math.min(delCost, insCost, subCost)
			
			// transposition detection
			if (i > 0 && j > 0 && needle[i] == haystack[j-1] && needle[i-1] == haystack[j]) {
				currRow[j + 1] = Math.min(cost, prevPrevRow[j-1] + (needle[i] == haystack[j] ? 0 : 1))
			} else
				currRow[j + 1] = cost
		}
		
		// swap rows for next iteration
		const tmpRow = prevPrevRow
		prevPrevRow = prevRow
		prevRow = currRow
		currRow = tmpRow
	}
	
	return Math.min(...prevRow)  //prevRow.reduce((acc, val) => acc < val ? acc : val)
}


/** Frequently used helper functions */
function Utils() {}
/** Extracts address or just the domain part from 'From' header string */
Utils.extractAddress = function(str, onlyDomain = false) {
	const addressRegex = /\w+([\.\+-]?\w+)*@\w+([\.-]?\w+)*(\.\w{2,6})+/g
	const results = str.match(addressRegex)
	var res = results !== null ? results[results.length-1].toLowerCase() : null
	if (res !== null && onlyDomain)
		res = res.substring(res.indexOf('@') + 1)  // return only domain
	
	return res
}
/** Converts comma-separated string to array */
Utils.listFromStr = function(str) {
	return str !== null ? str.split(/\s*,\s*/) : []
}
/** Converts string to canonical form, i.e., replace common non-alphanumeric chars with spaces, switch to lower-case and normalize */
Utils.canonicalize = (selector) => {
	return cheatChars.reduce((res, item) => {
		return res.replaceAll(item, '')
	}, selector)
	  .replaceAll(/\.|,|-|\\|\||\/|_|\+|"|'|%|@|#|\?|\*|=|\(|\)|\[|\]/g, ' ')
	  .replaceAll(/\s+/g, ' ').toLowerCase().normalize("NFKC")
}
/** Prevents prototype poisoning */
Utils.isObjectKeyValid = function(key) {
	return !['__proto__', 'constructor', 'prototype'].includes(key)
}


/** Manages suspicious borderline cases of SPF and Auth-Result header verifications */
function BorderlineHandler(configStr) {
	const config = !configStr ? 'strict' : configStr
	
	// separate mode from (optional) results
	const [mode, resultList] = config.split(':', 2)
	this.borderlineMode = mode !== 'strict' && mode !== 'relaxed' ? 'strict' : mode
	
	// parse result list
	this.borderlineResultList = resultList ? resultList.split(',') : []
	if (this.borderlineResultList[1] === '') this.borderlineResultList.pop()

	if (this.borderlineResultList.length == 0)  // default results
		this.borderlineResultList = ['softfail', 'temperror', 'neutral']
}
/** Returns borderline status through evaluating given auth method handler result */
BorderlineHandler.prototype.evaluate = function(result) {
	const isBorderline = ['softfail', 'temperror', 'neutral'].includes(result)
	var onBorderline = null
	if ((this.borderlineMode === 'strict' && this.borderlineResultList.includes(result))
	  || (this.borderlineMode === 'relaxed' && !this.borderlineResultList.includes(result)))
		onBorderline = 'flag'
	return {isBorderline: isBorderline, onBorderline: onBorderline}
}

/** Performs the verification of the DKIM-Signature headers */
function DKIMHandler(signerDomainList) {
	this.signerDomainList = signerDomainList
}
DKIMHandler.prototype.verify = function(msg) {
	// no crypto verification implemented
	
	if (this.signerDomainList.length == 0)
		return false

	if (this.signerDomainList[0] === 'self') {
		const fromAddress = Utils.extractAddress(msg.getField2('from'))
		if (!fromAddress) return false
		
		return msg.dkimHeaders.some((header) => {
			return header.d && fromAddress.endsWith('@'+ header.d.toLowerCase())
				&& (header.i === undefined || header.i.endsWith(header.d))
		})
	}
	
	return msg.dkimHeaders.some((header) => {
		if (!header.d) return false
		
		return this.signerDomainList.some((signer) => {
			if (signer[0] == '*')
				return header.d.toLowerCase().endsWith(signer.substring(1).toLowerCase())
			
			return signer.toLowerCase() == header.d.toLowerCase()
		}) && (header.i === undefined || header.i.endsWith(header.d))
	})
}
/** Parses the necessary message headers and adds them to the message object for later reuse */
DKIMHandler.parseMsgHeader = function(msg) {
	msg.dkimHeaders = msg.getFieldList('dkim-signature').map((headerStr) => {
		var header = {}
	  	headerStr.split(';').forEach((param, idx) => {
	  		const [key, val] = param.split('=', 2).map((item) => item.trim())
			
	    	if (Utils.isObjectKeyValid(key) && !header[key] && val) header[key] = val
	  	})
		return header
	})
	
	return msg.dkimHeaders.length > 0  // DKIM supported?
}

/** Performs the verification of the Received-SPF header */
function SPFHandler(borderlineMode = 'strict') {
	this.borderlineHandler = new BorderlineHandler(borderlineMode)
	this.borderlineCase = null
}
SPFHandler.prototype.verify = function(msg) {
	if (!msg.spfHeader) return false
	
	this.borderlineCase = null
	const result = msg.spfHeader.result
	if (!['pass', 'softfail', 'temperror', 'neutral'].includes(result))
		return false
	
	const returnPath = msg.getField2('return-path')
	var spfFrom = msg.spfHeader['envelope-from']
	if (!spfFrom || returnPath == '' || returnPath == '<>') {
		// compare helo identity with Received headers instead
		const heloHost = msg.spfHeader['helo']
		if (!heloHost) return false
		
		const receivedList = msg.getFieldList('received')
		const searchStr = 'from '+ heloHost.toLowerCase() +' '
		
		return receivedList.some((header) => header.startsWith(searchStr))
	}
	
	spfFrom = spfFrom.toLowerCase()
	if (!returnPath || !returnPath.toLowerCase().includes('<'+ spfFrom +'>'))
		return false
	
	// inform about borderline constraints or possible tampering, e.g., deliberate DNS timeouts
	this.borderlineCase = this.borderlineHandler.evaluate(result)
	
	return true
}
SPFHandler.parseMsgHeader = function(msg) {
	const headerStr = msg.getField2('received-spf')
	if (!headerStr) {
		//console.log('received-spf header not found')
		return false  // SPF not supported
	}
	
	msg.spfHeader = {}
	headerStr.split(';').forEach((param, idx) => {
		if (param.length == 0) return
		
		if (idx == 0) {
			// extract SPF result
			var spaceIdx = param.indexOf(' ')
			if (spaceIdx < 4) return  // malformed header
			
			msg.spfHeader.result = param.substring(0, param.indexOf(' ')).toLowerCase()
			
			// extract comment
			const commentStart = param.indexOf('('), commentEnd = param.indexOf(')')
			if (commentStart > 0 && commentEnd > commentStart)
				msg.spfHeader['comment'] = param.substring(commentStart+1, commentEnd).toLowerCase()
			
			// extract first key-Value pair
			spaceIdx = param.lastIndexOf(' ')
			if (spaceIdx < 4) return  // malformed header
			
			const [key, val] = param.substring(spaceIdx + 1).split('=', 2)
			if (Utils.isObjectKeyValid(key) && !msg.spfHeader[key] && val)
				msg.spfHeader[key] = val
			return
		}
		  
		const splitPos = param.indexOf('=')
		if (splitPos < 1) return  // malformed header
		
		const key = param.substring(0, splitPos).trim(),
			val = param.substring(splitPos + 1).replaceAll('"', '').trim()
		
		if (Utils.isObjectKeyValid(key) && !msg.spfHeader[key]) msg.spfHeader[key] = val
	}, this)
	
	if (!msg.spfHeader['envelope-from']) {
		// if 'envelope-from' key not specified, try to get it from comment
		const commentStr = msg.spfHeader['comment']
		if (!commentStr) return false  // insufficient header content
		
		const returnPathStart = commentStr.indexOf('domain of '),
			returnPathEnd = commentStr.indexOf(' ', returnPathStart + 10)
		if (returnPathStart > -1 && returnPathStart < returnPathEnd) {
			msg.spfHeader['envelope-from'] = commentStr.substring(returnPathStart + 10, returnPathEnd)
		} else if (['', '<>'].includes(msg.getField2('return-path'))) {
			// construct from helo identity instead, see RFC7208 section 2.4
			const heloHost = msg.spfHeader['helo']
			if (!heloHost) return false  // insufficient header content
			
			msg.spfHeader['envelope-from'] = 'postmaster@'+ heloHost
		} else return false
	}
	return true  // SPF supported
}

/** Performs the verification of the DKIM-Signature and Received-SPF headers respecting DMARC rules */
function DMARCHandler(configStr = '') {
	//this.alignmentModeStr = null
	[this.alignmentModeStr, this.organizationalDomain] = configStr.split(';')
	this.alignmentModeList = Utils.listFromStr(this.alignmentModeStr);
	//this.alignmentModeList = alignmentModeList
	[this.dkimMode, this.spfMode] = this.alignmentModeList
	
	this.dkimHandler = this.dkimMode == 's' ? new DKIMHandler(['self']) : null
	this.spfHandler = new SPFHandler()
	this.borderlineCase = null
}
DMARCHandler.prototype.verify = function(msg) {
	this.borderlineCase = null
	if (this.alignmentModeList.length != 2 || (!msg.spfHeader && !msg.dkimHeaders))
		return false
	
	const fromDomain = Utils.extractAddress(msg.getField2('from'), true),
		domainList = [fromDomain, '*.'+ fromDomain] // self and subdomain
	if (this.organizationalDomain) domainList.push(this.organizationalDomain) // orga domain
	const dkimHandler = this.dkimHandler || new DKIMHandler(domainList)
	
	if (!dkimHandler.verify(msg)) {
		const senderMailbox = msg.getField2('return-path') || msg.spfHeader['envelope-from']
		if (!senderMailbox) return false
		
		const rpathDomain = Utils.extractAddress(senderMailbox, true)
		const spfResult = this.spfHandler.verify(msg)
		this.borderlineCase = spfResult.borderlineCase
		
		return spfResult && (
			(this.spfMode == 's' && fromDomain == rpathDomain)
			|| (this.organizationalDomain  // c.f. RFC7489
			   ? (fromDomain == this.organizationalDomain
			   	  || fromDomain.endsWith('.'+ this.organizationalDomain))
			    && (rpathDomain == this.organizationalDomain
					|| rpathDomain.endsWith('.'+ this.organizationalDomain))
			   // just compare simple alignment instead of organizational domain
			   : (fromDomain == rpathDomain || rpathDomain.endsWith('.'+ fromDomain)
			    || fromDomain.endsWith('.'+ rpathDomain))
			   )
		)
	}
	return true
}
DMARCHandler.parseMsgHeader = function(msg) {
	if (!msg.dkimHeaders) DKIMHandler.parseMsgHeader(msg)
	if (!msg.spfHeader) SPFHandler.parseMsgHeader(msg)
	return msg.dkimHeaders.length > 0 || msg.spfHeader['envelope-from']
}

/** Performs the verification of the Authentication-Results headers */
function AuthenticationResultsHandler(protocolList = [], issuerList, borderlineMode) {
	if (!protocolList.every(protocol => ['dkim', 'spf', 'dmarc'].includes(protocol)))
		throw new Error('Unknown authRes method '+ protocolList +' in config file')
	if (!issuerList || issuerList.length == 0)
		throw new Error('Missing authResultsIssuers in config file')
	
	this.protocolList = protocolList
	this.issuerList = issuerList
	this.borderlineHandler = new BorderlineHandler(borderlineMode)
	this.borderlineCase = null
}
AuthenticationResultsHandler.prototype.verify = function(msg) {
	this.borderlineCase = null
	const fromAddress = Utils.extractAddress(msg.getField2('from'))
	var passed = true
	
	const evalProtocol = (protocol) => {
		if (!['pass', 'softfail', 'temperror', 'neutral'].includes(protocol.result)) {
			// detected auth failure in some header => verify() fails
			passed = false
			return false
		}
		
		switch(protocol.method) {
		  case 'dkim':  // checks for an exact match with sender domain
		  	const domain = (protocol['header.d'] || '').toLowerCase(),
				auid = (protocol['header.i'] || '').toLowerCase()
		  	if (!domain) {  // try to check AUID instead
				if (!auid) return false
				
				const domain = auid.substring(auid.indexOf('@'))
				if (!fromAddress.endsWith(domain))
					return false
			} else if (!fromAddress.endsWith('@'+ domain)
			  && !(auid && auid.endsWith(domain) && fromAddress.endsWith(auid)))
			    return false
			break
		  case 'spf':
		  	const mailfrom = protocol['smtp.mailfrom']
		  	if (!mailfrom) {  // compare helo identity with Received headers instead
				const heloHost = protocol['smtp.helo']
				if (!heloHost) return false
				
				const receivedList = msg.getFieldList('received')
				const searchStr = 'from '+ heloHost.toLowerCase() +' '
				if (receivedList.some((header) => header.startsWith(searchStr)))
					break
				return false
			}
		  	const returnPath = msg.getField2('return-path').toLowerCase()
		  	if (!returnPath || !returnPath.includes('<'+ mailfrom.toLowerCase() +'>'))
				return false
			break
		  case 'dmarc':
		  	const headerFrom = (protocol['header.from'] || '').toLowerCase()
			if (!headerFrom 
			  || !(fromAddress.endsWith('@'+ headerFrom)
			       || fromAddress.endsWith('.'+ headerFrom)))
			    return false
			break
		  default:
			return false
		}
		
		if (!this.borderlineCase || !this.borderlineCase.isBorderline
		  || (this.borderlineCase.isBorderline && !this.borderlineCase.onBorderline))
			this.borderlineCase = this.borderlineHandler.evaluate(protocol.result)
		//alertInfo(protocol.method)
		return true
	}
	
	// scan for all desired auth methods
	return this.protocolList.every((protocolName) => {
		// scan all Auth-Results headers
		return msg.authResHeaders.some((header) => {
		  // check for trusted issuers
		  const issuerMatched = this.issuerList.some((issuer) => {
		  	return header.issuer === issuer || header.issuer.endsWith('.'+ issuer)
			  || issuer === '*'
		  })
		  if (this.issuerList.length > 0 && !issuerMatched) return false
		  
		  // scan all methods within Auth-Results header
		  return header.methodList.some((protocol) => {
		    if (protocol.method != protocolName) return false
			
			return evalProtocol(protocol)
		  })
		})
	}) && passed
}
AuthenticationResultsHandler.parseMsgHeader = function(msg) {
	msg.authResHeaders = msg.getFieldList('authentication-results').map((headerStr) => {
	  var header = {methodList: []}
	  // remove text in brackets and split at semicolon method boundaries
	  headerStr.replaceAll(/\(.*?\)/g, '').split(';').forEach((protocolStr, methodIdx) => {
	    protocolStr = protocolStr.trim()
		
	    if (methodIdx == 0) {
	  	  header.issuer = protocolStr
		  return
	    }
		
	    var protocol = null
	    // split at spaces
	    protocolStr.split(/\s+/).forEach((param, idx) => {
			const splitPos = param.indexOf('=')
			if (splitPos < 1) return  // malformed header
			
			const key = param.substring(0, splitPos),
			  val = param.substring(splitPos + 1).replaceAll('"', '')
	  		//const [key, val] = param.split('=').map((item) => item.trim())
			if (idx == 0) {
			  protocol = {method: key, result: val}
			  return
			}
			
	  		if (Utils.isObjectKeyValid(key) && !protocol[key])
				protocol[key] = val
	    })
		if (protocol) header.methodList.push(protocol)
	  })
	  return header
	})
	
	return msg.authResHeaders.length > 0  // are authRes headers supported?
}

/** Performs checks on user-defined headers */
function HeaderMatchHandler(headerQueryList) {
	if (!Array.isArray(headerQueryList)) throw new Error('Wrong typed headerList in policy')
	
	this.headerQueryList = headerQueryList
}
HeaderMatchHandler.prototype.verify = function(msg) {
	return this.headerQueryList.some((headerQuery) => {
		return Object.entries(headerQuery).every(([headerName, queryStr]) => {
			return msg.getField2(headerName).includes(queryStr)
		})
	})
}


// Mail JXA API wrappers
function Message(raw) {
	this._raw = raw
	this._allHeadersStr = null
	this._id = null
	this._mailbox = null
}
Object.defineProperties(Message.prototype, {
	'id': {get: function() { return this._id || (this._id = this._raw.id()) }},
	'mailbox': {get: function() {
  		return this._mailbox || (this._mailbox = new Mailbox(this._raw.mailbox())) }},
	'junkMailStatus': {get: function() { return this._raw.junkMailStatus() },
  	  set: function(status) { this._raw.junkMailStatus = status }},
	'flagIndex': {get: function() { return this._raw.flagIndex() },
	  set: function(idx) { this._raw.flagIndex = idx }},
	'flaggedStatus': {get: function() { return this._raw.flaggedStatus() },
	  set: function(status) { this._raw.flaggedStatus = status }},
	'readStatus': {get: function() {
		if (this._raw && this._raw.readStatus) {
		  try {
			return this._raw.readStatus()
		  } catch (e) {
		  	console.log('readStatus exception: ['+ e.name +'] '+ e.message)
			return null
		  }
	    } else {
			console.log('raw message object not found')
			return null
		}
	}}
})
Message.prototype.moveToMailbox = function(box){
	this._raw.mailbox = box._raw()
	this._mailbox = new Mailbox(box._raw)
}
Message.prototype.getField = function(key){
	if (!Utils.isObjectKeyValid(key)) throw new Error('Invalid field key')
	
	if (this[key]) return this[key]

	try {
		// JXA API calls 'from' header 'sender'
		if (key == 'from') {
			const senderList = this._raw.headers.whose({name: {_equals: key}})
			this[key] = senderList.length > 0 ? senderList[0].content() : this._raw['sender']()
		} else if (key == 'sender') {  // get real 'sender' header
			//throw new Error('')
			const senderList = this._raw.headers.whose({name: {_equals: key}})
			this[key] = senderList.length > 0 ? senderList[0].content() : ''
		} else
			this[key] = this._raw[key]()  // try to get JXA API message property
	} catch (err) {  // get raw message header
	  	//const header = this._raw.headers.byName(key)
		const headersFiltered = this._raw.headers.whose({name: {_equals: key}}),
		  header = Array.prototype.reduce.call(headersFiltered, (acc, item) => {
		    return `${acc}\n ${item.content()}`
		  }, '').trim()
		
		this[key] = header//.content()
	}
	
	return this[key]
}
/** like getField(), but often faster; concatenation of all header occurrences is optional */
Message.prototype.getField2 = function(key, allOccurrences = false){
	if (!Utils.isObjectKeyValid(key)) throw new Error('Invalid field key')
	
	if (this[key]) return this[key]
	
	if (!this._allHeadersStr) {  // setup raw all headers string
		this._allHeadersStr = '\n'+ (this.source || this._raw.source())
		const headerEndPos = this._allHeadersStr.indexOf('\n\n')
		this._allHeadersStr = this._allHeadersStr.substring(0, headerEndPos + 1)
	}
	
	let res = '', header = getLocalHeader(key, this._allHeadersStr, 0)
	if (!header) return res  // header not found
	const content = header.headerContent
	
	if ((key == 'from' || key == 'subject' || key == 'to') && content.includes('=?')) {
	  // decode RFC2047 header parts
	  const components = content.split(' ')
	  let lastCompEncoded = false
	  components.forEach((comp, idx) => {
	  	const concatSpacer = idx == 0 ? '' : ' '
	 	if (!comp.startsWith('=?') || !comp.endsWith('?=')) {  // not encoded
			res += concatSpacer + comp
			lastCompEncoded = false
			return
		}
		
	 	const charset = comp.startsWith('=?utf-8?') || comp.startsWith('=?UTF-8?') ? 'utf-8'
		  : comp.startsWith('=?iso-8859-1?') || comp.startsWith('=?ISO-8859-1?') ? 'iso-8859-1'
		  : null
		if (!charset) {  // unsupported charset
			res += concatSpacer + comp
			lastCompEncoded = false
			return
		}
		
		let encodedStr = content.substring(charset.length + 5, comp.length - 2)
		const encoding = content.substring(charset.length + 3, charset.length + 5)
		if (encoding == 'q?' || encoding == 'Q?') {
			const decoded = qpDecodeUnicode(encodedStr.replaceAll('_', ' '), charset)
			res += lastCompEncoded ? decoded : concatSpacer + decoded
			lastCompEncoded = true
		} else if (encoding == 'b?' || encoding == 'B?') {
			const decoded = b64DecodeUnicode(encodedStr, charset)
			res += lastCompEncoded ? decoded : concatSpacer + decoded
			lastCompEncoded = true
		} else {  // unknown encoding
			res += concatSpacer + comp
			lastCompEncoded = false
		}
	  })
	} else res += content
	
	if (allOccurrences) {  // append all subsequent occurrences of header
	  while (header = getLocalHeader(key, this._allHeadersStr, header.lineEndPos + 1)) {
		if (!header) break
		res += '\n'+ header.headerContent
	  }
	  res = res.trim()
	}
	
	this[key] = res
	return res
}
/** returns list of all occurrences of specified header name */
Message.prototype.getFieldList = function(key){
	const headerList = this._raw.headers.whose({name: {_equals: key}}),
		headerArr = []
	Array.prototype.forEach.call(headerList, (item) => headerArr.push(item.content()) )
	return headerArr
}

function Mailbox(raw) {
	this._raw = raw
	this._name = null
	this._account = null
	this._messageList = null  // large array
	this._messages = null  // raw objects
	this.lazyMessageList = null
}
Object.defineProperties(Mailbox.prototype, {
	'name': {get: function(){ return this._name || (this._name = this._raw.name()) }},
	'account': {get: function(){
		return this._account || (this._account = new Account(this._raw.account())) }},
	'unreadCount': {get: function(){ return this._raw.unreadCount() }},
	'messageList': {get: function(){  // possibly very large array
		return this._messageList || (this._messageList = this._raw.messages()
		  .map(function(raw){ return new Message(raw)})) }},
	'messageCount': {get: function(){ return this._raw.messages.length }}
})
Mailbox.prototype.getMessageByIndex = function(idx){
	if (!this._messages) this._messages = this._raw.messages()
	if (!this.lazyMessageList) this.lazyMessageList = []
	if (!this.lazyMessageList[idx])
		this.lazyMessageList[idx] = new Message(this._messages[idx])
	return this.lazyMessageList[idx]
}
Mailbox.prototype.getMessageById = function(id){
	const msgList = this._raw.messages.whose({id: {_equals: id}})
	return msgList && msgList[0] ? new Message(msgList[0]) : null
}
Mailbox.prototype.getMessageListByDateInterval = function(minDate, maxDate){
	const msgList = this._raw.messages.whose({_and: [
		{dateReceived: {_greaterThanEquals: minDate}},
		{dateReceived: {_lessThanEquals: maxDate}}
	]})
	return Array.prototype.map.call(msgList, (rawMsg) => {
		return new Message(rawMsg)
	})
}
/** like getMessageListByDateInterval, but faster property retrieval due to circumvention of mailbox.whose() */
Mailbox.prototype.getMessageListByDateInterval2 = function(minDate, maxDate) {
	const totalMsgList = this._raw.messages(), listLen = totalMsgList.length
	const minTS = minDate.getTime(), maxTS = maxDate.getTime()
	let counter = 0
	const binarySearch = (searchTS, oldestIdx, newestIdx, boundaryType) => {
	  do {
		var pivotIdx = ((oldestIdx - newestIdx) >> 1) + newestIdx
		var pivotMsg = new Message(totalMsgList[pivotIdx]),
			pivotTS = new Date(pivotMsg.getField2('date')).getTime()
		if (pivotTS == searchTS) return pivotIdx
		if (pivotTS > searchTS) {  // found message is newer than searched timestamp
			newestIdx = pivotIdx + 1
		} else {  // found message is older than searched timestamp
			oldestIdx = pivotIdx - 1
		}
	  } while (oldestIdx - newestIdx > 0)
	  // here: newestIdx = oldestIdx
	  pivotIdx = newestIdx
	  pivotMsg = new Message(totalMsgList[pivotIdx]),
	  pivotTS = new Date(pivotMsg.getField2('date')).getTime()
	  // pivot is next to imaginary search item
	  if (boundaryType == 'oldest' && pivotTS < searchTS) pivotIdx--  // go to newer message
	  else if (boundaryType == 'newest' && pivotTS > searchTS) pivotIdx++  // go to older message
	  
	  return pivotIdx
	}
	
	// find oldest included message idx
	const oldestIdx = binarySearch(minTS, listLen - 1, 0, 'oldest')
	if (oldestIdx < 0) return []
	
	// find newest included message idx
	const newestIdx = binarySearch(maxTS, oldestIdx, 0, 'newest')
	if (newestIdx >= listLen || oldestIdx < newestIdx) return []
	
	// build filtered message array
	const size = oldestIdx - newestIdx + 1, arr = new Array(size)
	for (let i = 0; i < size; i++) {
		arr[i] = new Message(totalMsgList[i + newestIdx])
	}
	return arr
}

Mailbox.prototype.refreshMessageList = function(){
	this._messages = this._raw.messages()
	this._messageList = null
	this.lazyMessageList = null
}
Mailbox.prototype.getUnreadMessageList = function(){
	var unreadList = this._raw.messages.whose({readStatus: {_equals: false}})
	if (!unreadList) return []
	
	return Array.prototype.map.call(unreadList, (rawMsg) => {
		return new Message(rawMsg)
	})
}

function Account(raw) {
	this._raw = raw
	this._id = null
	this._name = null
	this._fullName = null
	this._emailAddresses = null
	this._mailboxes = null
}
Object.defineProperties(Account.prototype, {
	'id': {get: function(){ return this._id || (this._id = this._raw.id()) }},
	'name': {get: function(){ return this._name || (this._name = this._raw.name()) }},
	'fullName': {get: function(){
		return this._fullName || (this._fullName = this._raw.fullName()) }},
	'emailAddressList': {get: function(){
		return this._emailAddresses || (this._emailAddresses = this._raw.emailAddresses()) }},
	'mailboxList': {get: function(){
		return this._mailboxes || (this._mailboxes = this._raw.mailboxes()
		  .map(function(raw){return new Mailbox(raw)})) }},
	'enabled': {get: function(){
		try {
			return this._raw.enabled() === true
		} catch (e) {
			// account.enabled throws error on Big Sur
			//ActivityLog.log(e.message)
			return true
		}
	}}
})
Account.prototype.getMailboxByName = function(name) {
	if (name === undefined || name === null) return null
	
	const rawList = this._raw.mailboxes.whose({name: {_equals: name}})
	return rawList.length == 1 ? new Mailbox(rawList[0]) : null
}
Account.getAccountByName = function(name) {
	if (name === undefined || name === null) return null
	
	var rawList = null
	try {
		rawList = mail.accounts.whose({_and: [
		  {name: {_equals: name}},
		  {enabled: {_equals: true}}
		]})
	} catch (e) {
		rawList = mail.accounts.whose({name: {_equals: name}})
	}
	
	if (rawList.length > 1) throw new Error('found multiple accounts with name '+ name)
	
	return rawList.length == 1 ? new Account(rawList[0]) : null
}
/** Returns array of all enabled accounts */
Account.getAccountList = function() {
	var rawList = null
	try {
		rawList = mail.accounts.whose({enabled: {_equals: true}})
		//.whose({_match: [ObjectSpecifier().enabled, true]})
	} catch (e) {
		rawList = mail.accounts()
	}
	
	return Array.prototype.map.call(rawList, (rawAcc) => {
		return new Account(rawAcc)
	})  
}


/** script called from commandline */
function CliMode() {
	const args = $.NSProcessInfo.processInfo.arguments
	if (args.count < 3 || !args.js[2].js.startsWith('--')) return
	
	CliMode.isCliMode = true
	
	const findStartIdx = (cmd) => {
		return args.js.findIndex((arg) => arg.js == cmd)
	}
	/*
	// print all args for debugging
	const printArgs = () => {
		var list = ''
		for (let i=0; i<args.count; i++) {
			list += ' '+ args.js[i].js
		}
		$.printf(`${args.count} args: ${list}\n`)
	}
	printArgs()*/
	
	var cmdIdx = findStartIdx('--similarity')
	if (cmdIdx >= 2) {
		CliMode.similarity(args.js.slice(cmdIdx + 1))
		$.exit(0)
	} else if ((cmdIdx = CliMode.findArg(args.js, '--selector-stats', 5)).length > 0) {
		CliMode.selectorStats(cmdIdx)
		$.exit(0)
	} else if ((cmdIdx = findStartIdx('--account-details')) >= 2) {
		CliMode.accountDetails(args.js.slice(cmdIdx + 1))
		$.exit(0)
	} else if ((cmdIdx = findStartIdx('--match-details')) >= 2) {
		shouldAlertMatchDetails = true
		run()
		$.exit(0)
	} else if ((cmdIdx = findStartIdx('--help')) >= 2) {
		CliMode.printHelp()
		$.exit(0)
	}
}
/** find index of cmd in args list */
CliMode.findStartIdx = function(args, cmd) {
	return args.findIndex((arg) => arg.js == cmd)
}
/** find cmd flag in args list and argNum subsequent arguments correlated to cmd */
CliMode.findArg = function(args, cmd, argNum) {
	const startIdx = args.findIndex((arg) => arg.js ? arg.js === cmd : arg === cmd)
	if (startIdx < 0) return []
	return args.slice(startIdx + 1).map(arg => arg.js || arg)
}
/** set to boolean true if CLI mode has been detected */
CliMode.isCliMode = false
/** entry point for --similarity CLI flag */
CliMode.similarity = function(args) {
	if (args.count < 2) {
		$.printf('Usage: --similarity <needleStr> <haystackStr>\n')
		return
	}
	
	const needle = args[0].js, haystack = args[1].js,
		canonNeedle = Utils.canonicalize(needle),
		canonHaystack = Utils.canonicalize(haystack)
	const dlDist = Similarity.getDamerauLevenshtein(canonNeedle, canonHaystack),
		jwSim = Similarity.getFreeShiftJaroWinklerSim(canonNeedle, canonHaystack)
	
	$.printf(`Similarity results for "${needle}" and "${haystack}"\n`
		+`Canonicalized forms: "${canonNeedle}" and "${canonHaystack}"\n`
		+`Equality:\t\t\t${canonHaystack.includes(canonNeedle)}\n`
		+`Damerau-Levenshtein distance:\t${dlDist}\n`
		+`Jaro-Winkler similarity:\t${jwSim}\n`)
}

/** entry point for --selector-stats CLI flag */
CliMode.selectorStats = function(args) {
	if (args.length < 1) {
		$.printf('Usage: --selector-stats <selectorStr> [--similarity-mode <algo>:<threshold>] [--mailbox <account>:<mailbox>] [--period <daysPeriod>]\n')
		return
	}
	
	// extract selector string
	const selector = args[0],
		canonicalSelector = Utils.canonicalize(selector)
	
	// extract similarity mode params and setup comparison function
	const [simMode] = CliMode.findArg(args, '--similarity-mode', 1),
		[algo, thresholdStr] = simMode ? simMode.split(':') : [],
		threshold = Math.max(Number.parseFloat(thresholdStr), 0) || null
	const includesSelector = algo == 'dl' && threshold > 0 ? (haystack) => {
		return Similarity.getDamerauLevenshtein(canonicalSelector, haystack) <= threshold
	} : algo == 'jw' && threshold > 0 ? (haystack) => {
		return Similarity.getFreeShiftJaroWinklerSim(canonicalSelector, haystack) >= threshold
	} : (haystack) => {
		return haystack.includes(canonicalSelector)
	}
	
	// extract lookback/ date period
	const [period] = CliMode.findArg(args, '--period', 1)
	const [minDate, maxDate] = (() => {
	  if (period && period.includes(',')) {
		let [minDateStr, maxDateStr] = period.split(',', 2)
		const regex = /^\d+$/  // only digits => timestamp in msec
		if (regex.test(minDateStr)) minDateStr = Number.parseInt(minDateStr)
		if (regex.test(maxDateStr)) maxDateStr = Number.parseInt(maxDateStr)
		else maxDateStr += ' 23:59:59'
		return [new Date(minDateStr), new Date(maxDateStr)]
	  } else {
		const currentTimestamp = Date.now(),
		  daysCount = period ? Number.parseInt(period) : 0,
		  minTimestamp = currentTimestamp - (daysCount > 0 ? daysCount : 365) * 86400000
		return [new Date(minTimestamp), new Date(currentTimestamp)]
	  }
	})()
	if (minDate > maxDate || !minDate.getTime() || !maxDate.getTime()) {
		$.printf(`Invalid date interval: from ${minDate} to ${maxDate}\n`)
		return
	}
	
	// extract account and mailbox name
	const [accountAndMailbox] = CliMode.findArg(args, '--mailbox', 1),
		[accountName, mailboxName] = (accountAndMailbox ? accountAndMailbox : '').split(':')
	var account = null
	try {
		account = Account.getAccountByName(accountName)
		if (accountAndMailbox && !account) {
		  $.printf('Unknown account: '+ accountName +'\n')
		  return
		}
	} catch (e) {
		$.printf(e.message +'\n')
		return
	}
	const mailbox = account ? account.getMailboxByName(mailboxName) : null
	if (accountAndMailbox && !mailbox) {
		$.printf('Unknown mailbox: '+ mailboxName +'\n')
		return
	}
	
	
	const accountList = account ? [account] : Account.getAccountList(),
		skippedBoxList = ['trash', 'deleted', 'deleted messages', 'spam', 'junk', 'sent', 'sent messages', 'drafts', 'notes']
		
	// prints results as valid json object (without aggregated results)
	const useJsonOutput = args.includes('--json')
	// indicates if process is one of child processes running in parallel on adjacent sections
	const isChildProc = args.includes('--child')
		
	// setup authentication method handlers for fine-grained results
	const authHandlers = {
		/** perform and return verification step of handler with message and log problematic days */
		test: (handler, message, errorDayLog) => {
		  const res = handler.verify(message)
		  if (!res || (handler.borderlineCase && handler.borderlineCase.isBorderline)) {
			const date = new Date(/*message.getField('dateReceived')*/message.getField2('date'))
			errorDayLog.add(date.toISOString().substring(0, 10))
		  }
		  return res
		},
		dkimHandlerSelf: new DKIMHandler(['self']),
		dkimHandlerOthers: new DKIMHandler(['*']),
		spfHandler: new SPFHandler('strict:softfail'),
		dmarcHandlerStrict: new DMARCHandler('s,s'),
		dmarcHandlerRelaxed: new DMARCHandler('r,r'),
		authResHandlerDkim: new AuthenticationResultsHandler(['dkim'], ['*'], 'strict:softfail'),
		authResHandlerSpf: new AuthenticationResultsHandler(['spf'], ['*'], 'strict:softfail'),
		authResHandlerDmarc: new AuthenticationResultsHandler(['dmarc'], ['*'], 'strict:softfail')
	}
	
	const senderAddressMap = new Map()  // stores results of all matching messages
	const getOrCreateSenderItem = CliMode.selectorStats.getOrCreateSenderItem
	
	$.printf(`Selector stats for "${canonicalSelector}" (canonicalized)\n`)
	$.printf(`\n${accountList.length} accounts:\n`)
	
	const execPath = $.NSBundle.mainBundle.executablePath.js,
		taskQueue = new TaskQueue(execPath)
	
	// build argument list base reused in every child task
	const rawArgs = $.NSProcessInfo.processInfo.arguments
	const argsBase = [rawArgs.js[1].js, '--selector-stats', selector, '--json', '--child']
	if (simMode) argsBase.push('--similarity-mode', simMode)
	if (accountAndMailbox) argsBase.push('--mailbox', accountAndMailbox)
	
	// analyze accounts and mailboxes
	const perfStartTime = Date.now()
	accountList.forEach((account) => {
		$.printf(`Searching ${account.name}...\n`)
		const accountDomainList = account.emailAddressList.map((address) => {
			return Utils.extractAddress(address, true)
		})
		
		const mailboxList = mailbox ? [mailbox] : account.mailboxList
		mailboxList.forEach((mailbox) => {
			const mailboxName = mailbox.name.toLowerCase()
			if (skippedBoxList.includes(mailboxName)) return
			
			const messageList = mailbox.getMessageListByDateInterval2(minDate, maxDate)//mailbox.messageList()
			
			// serial implementation
			if (isChildProc || messageList.length <= 50) {
			  for (const message of messageList) {
				CliMode.selectorStats.analyzeMessage(message, account, mailbox, senderAddressMap, includesSelector, authHandlers)
			  }
			  $.printf(messageList.length+' messages\n')
			  return
			}
			
			// parallel implementation (NSTask)
			$.printf('message count: '+ messageList.length +'\n')
			const taskCount = Math.min(Math.ceil(mailbox.messageCount / 500), 6),
				messagesPerTask = Math.max(Math.floor(messageList.length / taskCount), 1),
				taskResultList = []
			let lastLeftTs = -1  // timestamp of previous endIdx
			
			// enqueue parallel tasks
			for (let taskIdx = 0; taskIdx < taskCount; taskIdx++) {
				// determine task boundaries within messageList
				const startIdx = taskIdx * messagesPerTask
				const endIdx = taskIdx < taskCount-1 ? startIdx + messagesPerTask - 1
				 : messageList.length - 1
				$.printf(`new Task startIdx: ${startIdx}, endIdx: ${endIdx}\n`)
				
				// convert boundaries to timestamps and avoid intersection of task intervals
				const rawRightTs = new Date(messageList[startIdx].getField2('date')).getTime()
				const rightTs = rawRightTs == lastLeftTs ? rawRightTs - 1 : rawRightTs,
					leftTs = new Date(messageList[endIdx].getField2('date')).getTime()
				lastLeftTs = leftTs
				$.printf(leftTs +','+ rightTs +'\n')
				
				CliMode.selectorStats.enqueueTask(taskQueue, taskIdx,
				  argsBase.concat('--period', leftTs +','+ rightTs), senderAddressMap)
			}
		})
	})
	taskQueue.wait()
	$.printf(`\nComputation time: ${(Date.now() - perfStartTime) / 1000} sec\n`)
	
	// convert stats structure to json compatible object and print
	if (useJsonOutput) {
		let jsonObj = {}
		senderAddressMap.forEach((stats, senderAddress) => {
			jsonObj[senderAddress] = CliMode.selectorStats.statsToJsonObj(stats)
		})
		$.printf('\n\n'+ JSON.stringify(jsonObj))
		return
	}
	
	// print human-readable results
	CliMode.selectorStats.printResults(senderAddressMap)
}
/** adds a new task for the given time interval to the working queue and aggregate results */
CliMode.selectorStats.enqueueTask = function(taskQueue, taskIdx, args, senderAddressMap) {
  taskQueue.async(args, (res, error) => {
	$.printf('Task '+ taskIdx +' finished\n')
	if (res === null) {
		$.printf(`No result, error: ${error.localizedDescription.js}\n`)
		return
	}
	
	// extract json result
	const jsonStartIdx = res.lastIndexOf('\n\n'),
		jsonStr = res.substring(jsonStartIdx + 2)
	let jsonObj = null
	try {
		jsonObj = JSON.parse(jsonStr)
	} catch (err) {
		$.printf(err.message +'\n')
		return
	}
	//$.printf(res)
	const arrayToSet = (obj, key) => { obj[key] = new Set(obj[key]) }
	for (const address in jsonObj) {
		// convert certain json properties back to Sets and Maps
		const addressObj = jsonObj[address]
		arrayToSet(addressObj, 'mailboxLog')
		addressObj.replyToLog = new Map(addressObj.replyToLog)
		arrayToSet(addressObj.dkim, 'signerLog')
		arrayToSet(addressObj.authRes, 'issuerLog')
		arrayToSet(addressObj, 'unsupportedDayLog')
		arrayToSet(addressObj, 'errorDayLog')
		
		// add partial results to aggregated senderAddressMap
		const accStats = CliMode.selectorStats.getOrCreateSenderItem(senderAddressMap, address)
		CliMode.selectorStats.addSenderStatsToAggregate(accStats, addressObj)
	}
  })
}
/** get existing address item from senderAddressMap or create and return a new empty one */
CliMode.selectorStats.getOrCreateSenderItem = function(senderAddressMap, senderAddress) {
	var senderItem = senderAddressMap.get(senderAddress)
	if (senderItem) return senderItem
	
	// add new address to map
	senderItem = {
	  total: 0,
	  mailboxLog: new Set(),
	  replyToLog: new Map(),
	  dkim: {self: 0, others: 0, signerLog: new Set()},
	  spf: {pass: 0, softfail: 0, temperror: 0},
	  dmarc: {strict: 0, relaxed: 0},
	  authRes: {dkim: {pass: 0, softfail: 0, temperror: 0},
		spf: {pass: 0, softfail: 0, temperror: 0},
		dmarc: {pass: 0, softfail: 0, temperror: 0},
		issuerLog: new Set()
	  },
	  unsupportedDayLog: new Set(),
	  errorDayLog: new Set()
	}
	senderAddressMap.set(senderAddress, senderItem)
	return senderItem
}
/** apply borderline results per authentication method verification */
CliMode.selectorStats.applyBorderlineResult = function(resultObj, borderlineResult) {
	if (borderlineResult.isBorderline) {
		if (borderlineResult.onBorderline)
			resultObj.softfail++
		else resultObj.temperror++
	} else
		resultObj.pass++
}
/** test message for selector match and analyze support for authentication methods */
CliMode.selectorStats.analyzeMessage = function(message, account, mailbox, senderAddressMap, includesSelectorFcn, authHandlers) {
	/*const receiveTime = Date.parse(message.getField('dateReceived'))
	if (receiveTime  < minTimestamp) break*/
	
	var from = message.getField2('from'),
		canonicalFrom = Utils.canonicalize(from)
	//if (!canonicalFrom.includes(canonicalSelector)) continue
	if (!includesSelectorFcn(canonicalFrom)) return
	
	const senderAddress = Utils.extractAddress(from),
		senderItem = CliMode.selectorStats.getOrCreateSenderItem(senderAddressMap, senderAddress),
		replyTo = message.getField2('reply-to'),
		unsupportedDayLog = senderItem.unsupportedDayLog,
		errorDayLog = senderItem.errorDayLog,
		msgDateStr = new Date(message.getField2('date')).toISOString().substring(0, 10)
	
	// update sender address results
	senderItem.total++
	senderItem.mailboxLog.add(account.name +':'+ mailbox.name)
	
	// log dates of messages with reply-to header different from sender address
	if (replyTo != '' && replyTo != senderAddress
	  && !replyTo.endsWith('<'+ senderAddress +'>')) {
		const replyToAddress = Utils.extractAddress(replyTo)
		if (!senderItem.replyToLog.has(replyToAddress)) {
			//const date = new Date(/*message.getField('dateReceived')*/message.getField2('date'))
			senderItem.replyToLog.set(replyToAddress,
			  msgDateStr)
		}
	}
	
	// check message authentication methods
	if (!DKIMHandler.parseMsgHeader(message)) unsupportedDayLog.add(msgDateStr)
	else if (authHandlers.test(authHandlers.dkimHandlerSelf, message, errorDayLog))
		senderItem.dkim.self++
	else if (authHandlers.test(authHandlers.dkimHandlerOthers, message, errorDayLog)) {
		senderItem.dkim.others++
	}
	message.dkimHeaders.forEach(header => {
		senderItem.dkim.signerLog.add(header.d || header.i)
	})
	
	if (!SPFHandler.parseMsgHeader(message)) unsupportedDayLog.add(msgDateStr)
	else if (authHandlers.test(authHandlers.spfHandler, message, errorDayLog)) {
		CliMode.selectorStats.applyBorderlineResult(senderItem.spf, authHandlers.spfHandler.borderlineCase)
	}
	
	if (!DMARCHandler.parseMsgHeader(message)) unsupportedDayLog.add(msgDateStr)
	else {
	  if (authHandlers.test(authHandlers.dmarcHandlerStrict, message, errorDayLog)) {
		senderItem.dmarc.strict++
	  }
	  if (authHandlers.test(authHandlers.dmarcHandlerRelaxed, message, errorDayLog)) {
		senderItem.dmarc.relaxed++
	  }
	}
	
	if (!AuthenticationResultsHandler.parseMsgHeader(message))
		unsupportedDayLog.add(msgDateStr)
	else {
	  if (authHandlers.test(authHandlers.authResHandlerDkim, message, errorDayLog)) {
		CliMode.selectorStats.applyBorderlineResult(senderItem.authRes.dkim, authHandlers.authResHandlerDkim.borderlineCase)
	  }
	  if (authHandlers.test(authHandlers.authResHandlerSpf, message, errorDayLog)) {
		CliMode.selectorStats.applyBorderlineResult(senderItem.authRes.spf, authHandlers.authResHandlerSpf.borderlineCase)
	  }
	  if (authHandlers.test(authHandlers.authResHandlerDmarc, message, errorDayLog)) {
		CliMode.selectorStats.applyBorderlineResult(senderItem.authRes.dmarc, authHandlers.authResHandlerDmarc.borderlineCase)
	  }
	}
	
	// log authRes header issuer
	message.authResHeaders.forEach((header) => {
		if (header.issuer) senderItem.authRes.issuerLog.add(header.issuer)
	})
}
/** add partial results to aggregated with respect to property types */
CliMode.selectorStats.addSenderStatsToAggregate = function(agg, stats) {
	if (!stats) return
	
	const propertyKeyList = Object.keys(agg)
	for (const key of propertyKeyList) {
	  const aggVal = agg[key]
	  if (typeof aggVal == 'number')
		agg[key] += stats[key]
	  else if(aggVal instanceof Set)
	  	stats[key].forEach((sVal, sKey) => aggVal.add(sVal))
	  else if(aggVal instanceof Map) {
	  	stats[key].forEach((sVal, sKey) => {
		  if (!aggVal.has(sKey))
		  	aggVal.set(sKey, sVal)
		  else {
		  	const aggVal = agg[key].get(sKey)
			if (typeof aggVal == 'number')
				agg[key] += sVal
			else if (typeof aggVal == 'string')
				agg[key].set(sKey, sVal)  // replace content
			else if (typeof aggVal == 'object')
			  CliMode.selectorStats.addSenderStatsToAggregate(aggVal, stats[key])
		  }
		})
	  } else if (typeof aggVal == 'object')
		CliMode.selectorStats.addSenderStatsToAggregate(aggVal, stats[key])
	}
}
/** convert stats object to JSON object including Sets and Maps */
CliMode.selectorStats.statsToJsonObj = function(source) {
	const target = {}
	Object.keys(source).forEach((key) => {
	  const val = source[key]
	  if (val instanceof Set) {
		target[key] = Array.from(val)
	  } else if (val instanceof Map) {
		const map = []
		val.forEach((mapVal, mapKey) => {
			map.push([mapKey, mapVal])
		})
		target[key] = map
	  } else if (typeof val === 'number' || typeof val === 'string') {
		target[key] = val
	  } else if (typeof val === 'object') {
		target[key] = CliMode.selectorStats.statsToJsonObj(val)
	  }
	})
	return target
}
/** print sender stats results */
CliMode.selectorStats.printResults = function(senderAddressMap) {
	// create percentage str
	const round = (num) => {
		return (num * 100).toFixed(1)
	}
	// create auth method string including borderline results
	const getMethodResultStr = (resultObj, total) => {
		return `{pass: ${resultObj.pass} (${round(resultObj.pass/total)}%%), softfail: ${resultObj.softfail} (${round(resultObj.softfail/total)}%%), temperror: ${resultObj.temperror} (${round(resultObj.temperror/total)}%%)}`
	}
	// create string of Set items
	const joinSetItems = (set) => {
		if (set.size > 0)
			return set.keys().reduce((acc, curr) => acc +', '+ curr)
		return ''
	}
	// create string of Map items
	const joinMapItems = (map) => {
		var res = ''
		map.forEach((value, key) => {
			res += `, ${key} (${value})`
		})
		if (res[0] === ',') res = res.slice(2)
		return res
	}
	
	const domainMap = new Map()  // domain-aggregated results
	const summableStatsKeyList = ['dkim', 'spf', 'dmarc', 'authRes']
	const addSenderStatsToAggregate = CliMode.selectorStats.addSenderStatsToAggregate
	
	const createResultItemString = (stats, senderStr) => {
		const total = stats.total
		var res = `From: ${senderStr} (total message count: ${total})`
		if (stats.addressLog)
			res += '\nFrom addresses count: '+ stats.addressLog.size
		if (stats.mailboxLog)
			res += '\nMailboxes: '+ joinSetItems(stats.mailboxLog)
		if (stats.replyToLog && stats.replyToLog.size > 0)
			res += '\nReply-To addresses: '+ joinMapItems(stats.replyToLog)
		
		res += `\nDKIM: {\n self: ${stats.dkim.self} (${round(stats.dkim.self/total)}%%), onlyOthers: ${stats.dkim.others} (${round(stats.dkim.others/total)}%%),\n signers: ${joinSetItems(stats.dkim.signerLog)}\n}`
			+ `\nSPF: ${getMethodResultStr(stats.spf, total)}`
			+ `\nDMARC: {s,s: ${stats.dmarc.strict} (${round(stats.dmarc.strict/total)}%%), r,r: ${stats.dmarc.relaxed} (${round(stats.dmarc.relaxed/total)}%%)}`
			+ `\nauthRes: {\n dkim: ${getMethodResultStr(stats.authRes.dkim, total)}, `
			+ `\n spf: ${getMethodResultStr(stats.authRes.spf, total)}, `
			+ `\n dmarc: ${getMethodResultStr(stats.authRes.dmarc, total)},\n issuers: `
		res += joinSetItems(stats.authRes.issuerLog)
		res += '\n}'
		if (stats.unsupportedDayLog && stats.unsupportedDayLog.size > 0)
			res += '\nMissing headers: '+ joinSetItems(stats.unsupportedDayLog)
		if (stats.errorDayLog && stats.errorDayLog.size > 0)
			res += '\nError days: '+ joinSetItems(stats.errorDayLog)
		res += '\n\n\n'
		
		return res
	}
	
	$.printf(`\nResults: ${senderAddressMap.size}\n`)
	if (senderAddressMap.size == 0) {
		$.printf('\nNo results found\n\n')
		return
	}
	senderAddressMap.forEach((stats, senderAddress) => {
		const total = stats.total
		var res = createResultItemString(stats, senderAddress)
		
		$.printf(res)  // print results per address
		
		// produce domain-aggregated results
		const senderDomain = Utils.extractAddress(senderAddress, true)
		var domainAggregate = domainMap.get(senderDomain)
		if (!domainAggregate) {
			domainAggregate = {
			  addressLog: new Set(),
			  total: 0,
			  dkim: {self: 0, others: 0, signerLog: new Set()},
		  	  spf: {pass: 0, softfail: 0, temperror: 0},
		  	  dmarc: {strict: 0, relaxed: 0},
		  	  authRes: {dkim: {pass: 0, softfail: 0, temperror: 0},
				spf: {pass: 0, softfail: 0, temperror: 0},
				dmarc: {pass: 0, softfail: 0, temperror: 0},
				issuerLog: new Set()
		  	}}
			domainMap.set(senderDomain, domainAggregate)
		}
		
		domainAggregate.addressLog.add(senderAddress)
		domainAggregate.total += stats.total
		for (const key of summableStatsKeyList) {
			addSenderStatsToAggregate(domainAggregate[key], stats[key])
		}
	})
	
	if (domainMap.size == senderAddressMap.size) return  // no meaningful aggregation
	
	// print domain-aggregated results
	$.printf(`\nDomain-aggregated results: ${domainMap.size}\n`)
	domainMap.forEach((domainStats, domainName) => {
		var res = ''
		res += createResultItemString(domainStats, 'Domain '+ domainName)
		$.printf(res)
	})
}

/** entry point for --account-details CLI flag */
CliMode.accountDetails = function(args) {
	const accountList = Account.getAccountList()
	accountList.forEach(account => {
	  const emailAddressList = account.emailAddressList,
		mailboxList = account.mailboxList.reduce((acc, curr) => {
			return (acc.name ? `${acc.name} (${acc.messageCount})` : acc) +', ' + `${curr.name} (${curr.messageCount})`
		})
	  $.printf(`Name: ${account.name}\nAddresses: ${emailAddressList.join(', ')}\nMailboxes: ${mailboxList}\n\n`)
	})
}
/** entry point for --help CLI flag */
CliMode.printHelp = function() {
	$.printf('Usage:\n\n'
	  +'--selector-stats <selectorStr> [--similarity-mode <algo>:<threshold>] [--mailbox <account>:<mailbox>] [--period <daysPeriod>]\nPrints all sender addresses and authentication statistics for messages for the given account/mailbox tuple (default: all accounts) that matched the selector string within the given period of days (default: 365; alternative date interval syntax: <startDate>,<endDate> both of ISO format YYYY-MM-DD). The similarity mode can be changed to "dl" or "jw" (default: "canonical"). The days of occurence of results other than "pass" are listed as "Error days". Note: This operation can take up some time for large mailboxes!\n\n'
	  +'--similarity <needleStr> <haystackStr>\nApplies all similarity algorithms on both provided strings and prints the results.\n\n'
	  +'--account-details\nPrints address and mailbox details for all enabled accounts.\n\n'
	  +'--match-details\nTemporarily sets the `shouldAlertMatchDetails` config to `true` and runs the filter process.\n\n'
	  +'--help\nPrints this help.\n')
}


/** Process-based parallel execution queue comprising multiple instances of the same executable (path) and max active processes */
function TaskQueue(path, maxProcs = 6) {
	this.executablePath = path
	this._readyQueue = []
	this._activeQueue = []
	this._maxProcs = maxProcs
	this._activeProcsCount = 0
}
/** add task defined by args and completion handler to queue and launch if possible; completion handler receives stdout of the task and NSError object */
TaskQueue.prototype.async = function(args, completion) {
	const task = $.NSTask.alloc.init
	task.executableURL = $.NSURL.URLWithString('file://'+ this.executablePath)
	task.arguments = args
	const pipe = $.NSPipe.pipe
	task.standardOutput = pipe
	task.terminationHandler = (task) => {
		$.printf('task terminated with status '+ task.terminationStatus +'\n')
	}
	
	this._readyQueue.push({task: task, args: args, pipe: pipe, completion: completion})
	this._launchNext()
}
/** launch next task from internal ready queue */
TaskQueue.prototype._launchNext = function(actIdx) {
	if (this._readyQueue.length == 0 || this._activeProcsCount == this._maxProcs) return
	
	const taskDesc = this._readyQueue.splice(0, 1)[0]
	let error = $()
	taskDesc.task.launchAndReturnError(error)
	if (!error.isNil()) console.log(error.code)
	//$.printf('launched task\n')
	
	if (actIdx === undefined) this._activeQueue.push(taskDesc)
	else this._activeQueue[actIdx] = taskDesc
	this._activeProcsCount++
}
/** wait for all tasks to finish that are stored in internal ready queue via spin lock */
TaskQueue.prototype.wait = function() {
  while (this._readyQueue.length > 0 || this._activeProcsCount > 0) {
	this._activeQueue.forEach((taskDesc, idx) => {
		//taskDesc.task.waitUntilExit()
		if (!taskDesc || taskDesc.task.running) return
		
		this._activeQueue[idx] = null
		this._activeProcsCount--
		this._launchNext(idx)
		//$.printf('task finished with status '+ taskDesc.task.terminationStatus +' '+ (taskDesc.task.terminationReason == $.NSTaskTerminationReasonExit) + '\n')
		const error = $(),
			data = taskDesc.pipe.fileHandleForReading.readDataToEndOfFileAndReturnError(error)
		if (data.isNil()) taskDesc.completion(null, error)
		else {
			const resStr = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding)
			//$.printf('got result\n')
			taskDesc.completion(ObjC.unwrap(resStr), null)
		}
	})
	delay(0.25)
	//$.printf('readyQueue.len:'+ this._readyQueue.length +'\n')
  }
}
