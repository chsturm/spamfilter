/*
spamfilter for Apple Mail.app on macOS
Copyright (c) 2025 Christian Sturm

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
const shouldLogActivity = false  // true: log details about message tests to file
const mutexLifetime = 600  // duration in seconds after which a mutex lock will be reset


const mail = Application.currentApplication().name == "Mail"
	? Application.currentApplication() : Application("Mail")
mail.includeStandardAdditions = true
if (!mail.running()) {
	delay(10)
	if (!mail.running()) throw "Mail.app not running"
}


ObjC.import('Foundation')
//ObjC.import('stdlib')
ObjC.import('stdio')
ObjC.import('unistd')

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
		mail.displayDialog("No rules file found!", {withIcon: "caution", givingUpAfter: 10})
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
	try {
		var config = this.loadConfigFromFile()
	} catch (e) {
		console.log(e.name +': '+ e.message)
		if (e instanceof SyntaxError && !config)
			mail.displayDialog("JSON syntax error in rules file on line "+ e.lineNumber +": "
				+ e.message)
	}
	
	if (!config || !config.rulesList) return false
	
	if (config.shouldAlertMatchDetails === true || config.shouldAlertMatchDetails !== "false")
		shouldAlertMatchDetails = config.shouldAlertMatchDetails
	this.rulesList = config.rulesList
	return true
}

/** Get rules for given email address resp. account */
RulesHandler.prototype.getRulesForAddress = function(address) {
	return this.rulesList.find(function(rule) {
		return address === rule.email
	})
}


/** handler called by terminal via osascript -l JavaScript <path> */
function run () {
	mail.downloadHtmlAttachments = false
	const accountList = mail.accounts()  //.whose({_match: [ObjectSpecifier().enabled, true]})()
	var shouldDisplayNotification = false
	if (!rulesHandler.loadRulesList()) return
	
	accountList.forEach(function(account){
		try {
			if (account.enabled() === false) return
		} catch (e) {
			// account.enabled throws error on Big Sur
			//ActivityLog.log(e.message)
		}
		
		const filterHandler = new SpamFilterHandler()
		filterHandler.account = new Account(account)
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
		shouldDisplayNotification |= filterHandler.hasNewMessages
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
		messageList = messages.map(function(raw){return new Message(raw)})
	else
		messageList = [new Message(messages[0])]
	
	const filterHandler = new SpamFilterHandler()
	filterHandler.filterMessageList(messageList)
	
	// return if no rules exist
	if (!filterHandler.mailboxRule) {
		ActivityLog.finish()
		return
	}
	
	/* no bug circumvention needed if only one message in list or user-selected list,
	   already in trash or other spamfilter instance running on account
	*/
	// try to get lock of current account if more messages are available to filter
	const accountMutex = new RunCoordinator(filterHandler.mailbox.account.id)
	if (messageList.length > 1  // user-selected list
		  || ["Deleted Messages", "Trash"].includes(filterHandler.mailbox.name)
		  || accountMutex.tryLock() !== true) {
		if (accountMutex.gotLock() === false)
			ActivityLog.log("no-lock/"+ filterHandler.mailboxRule.email)
		ActivityLog.finish()
		return
	}
	if (accountMutex.gotLock() === true)
		ActivityLog.log("got-lock/"+ filterHandler.mailboxRule.email)
	
	// filter messages not dealt with above due to bugs in Mail.app
	// => filter the whole mailbox of the first message given in messages arg
	mail.checkForNewMail(filterHandler.mailbox.account)
	delay(1)
	filterHandler.mailbox.refreshMessageList()
	if (messages.length > 1 || filterHandler.mailbox.unreadCount > 0)
		filterHandler.filterCurrentMailbox()
	
	// also filter custom mailboxes having some rules defined
	filterHandler.filterAccountMailboxes()
	
	accountMutex.unlock()
	ActivityLog.finish()
	if (filterHandler.hasNewMessages) newMailNotification()
}

/** Display notification for new messages in mailboxes other than INBOX */
function newMailNotification(retryOnError = true) {
	const app = Application.currentApplication()  // displayNotification only works in currApp
	app.includeStandardAdditions = true
	try {
		app.displayNotification('New messages in Mail.app', {withTitle: "Spamfilter"})
	} catch (err) {
		console.log("Notification error: "+ err.message)
		if (retryOnError) newMailNotification(false)
	}
}

/** Handles all spam filter operations on single messages, message lists, mailboxes and accounts
*/
function SpamFilterHandler () {
	this.mailbox = null
	this.mailboxRule = null
	this.accountRules = null
	this.account = null
	this.accountMailboxes = null
	this.invokedBy = ''
	this.hasNewMessages = false
}
/** Applies spam filter operation on given message list;
	Defines mailbox, rules and account properties for subsequent filtering
*/
SpamFilterHandler.prototype.filterMessageList = function(messageList) {
	if (!Array.isArray(rulesHandler.rulesList)) {
		mail.displayDialog("No rules list found in json file")
		return
	}
	
	for (var message of messageList) {
		// search matching rule based on email address
		const mailbox = message.mailbox
		const rule = this.getRuleAndAccountFromMailbox(mailbox)
	
		if (!rule) {
			ActivityLog.log("no-rules/"+ this.account.emailAddressList[0])
			return
		}
		
		// store mailbox and account rule of first message to test remaining ones
		if (!this.mailbox) {
			this.mailbox = mailbox
			this.mailboxRule = rule
			//messageMeta.accountRules = accountRules
			if (Progress) Progress.description = rule.email
			delay(0.2)
		}
		
		ActivityLog.logMessage(message, "firstrun-test/"+ rule.email)
		this.filterMessage(rule, message)
	}
}

/** Get account rules from general rules list */
SpamFilterHandler.prototype.loadAccountRules = function() {
	if (!this.account) {
		ActivityLog.log("loadAccountRules() failed: this.account not defined");
		return false
	}
	const accountAddressList = this.account.emailAddressList
	
	// search account specific rules object
	var accountRules = null
	for (let address of accountAddressList) {
		if (accountRules = rulesHandler.getRulesForAddress(address)) break
	}
	if (!accountRules) return false
	this.accountRules = accountRules
	
	// add default INBOX rule to mailboxList if not already included
	if (!accountRules.mailboxList) accountRules.mailboxList = []
	if (accountRules.mailboxList.some(function(rule){
		return rule.name === 'INBOX'
	})) return true
	
	accountRules.mailboxList.push({
		name: 'INBOX',
		email: accountRules.email,
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

/** Applies spam filter operation on given message */
SpamFilterHandler.prototype.filterMessage = function(rule, message) {
	// delete message as soon as a blacklist match is detected
	
	if (testSelfAddressedForFullName(rule.email, message)
		 || testSenderForFullName(rule.fromWhitelist, message)
		 || testMessageField('from', rule.senderBlacklist, message)
		 || testMessageField('subject', rule.subjectBlacklist, message)
		 || testHeaders(rule.headerBlacklist, message)
		 || testMessageField('source', rule.contentBlacklist, message)) {
		// mark message as processed by spamfilter for debugging
		/*message.flagIndex = 6;	// grey
		message.flaggedStatus = true;*/
				
		this.moveToTrash(message)
		delay(0.6)  // avoid DoS of your mail server
		return true
	} else {
		//console.log("No blacklist matches found")
		return false
	}
}
/** moves specified message to trash folder of its mail account */
SpamFilterHandler.prototype.moveToTrash = function(mes) {
	mes.junkMailStatus = true
	//mes.deletedStatus = true // message lost in the Nirwana

	if (!this.account) mail.displayDialog("Account of mailbox undefined")
	
	// get trash mailbox of account
	const boxList = this.accountMailboxes || (this.accountMailboxes = this.account.mailboxList)
	if (!boxList || boxList.length === 0) mail.displayDialog("Mailbox list undefined")
	
	var trash = boxList.find(function(box){
		const boxName = box.name, exists = boxName.includes("Deleted Messages")
		return exists || boxName.includes("Trash")
	});
	if (!trash) {
		mail.displayDialog("Trash undefined for account " + this.account.name)
		return
	}

	mes.moveToMailbox(trash)
	//mail.checkForNewMail(account)
}


/** Applies spam filter operation once on given mailbox using given rule */
SpamFilterHandler.prototype.filterMailbox = function(boxRule, mailbox) {
	// message list: chronological join of 'Deleted Messages' since startup and 'INBOX' 
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
	return true
}

/** Applies spam filter operation on predefined mailbox, e.g., by filterMessageList().
	This method is more reliable than filterMailbox() due to bugs in Mail.app
*/
SpamFilterHandler.prototype.filterCurrentMailbox = function() {
	if (!this.mailbox || !this.account) return
	
	this.accountMailboxes = this.account.mailboxList
	this.filterMailboxInLoops(this.mailboxRule, this.mailbox)
}

/** Applies multiple iterations of spam filter operation on given mailbox using given rule */
SpamFilterHandler.prototype.filterMailboxInLoops = function(boxRule, mailbox) {
	// try multiple times to catch all unread messages in INBOX
	var iterations = 2
	for (var i=0; i<iterations; i++) {
		delay(0.5)
		var unreadCount = mailbox.unreadCount
		if (unreadCount > 0) {
			ActivityLog.log(this.invokedBy +"more-messages/"+ boxRule.email +"/box."
				+ mailbox.name +"/loop."+ i +": " + unreadCount)
			if (Progress) Progress.description = boxRule.email +": Mailbox test"
			if (!this.filterMailbox(boxRule, mailbox) && iterations == 2) iterations = 3
		} else break
	}
	
	// display notification if new messages in secondary mailboxes
	if (mailbox.name == 'INBOX') return
	if (mailbox.unreadCount > 0) this.hasNewMessages = true
}

/** Applies spam filter operation on custom mailboxes of predefined account */
SpamFilterHandler.prototype.filterAccountMailboxes = function() {
	if (!this.account || !this.accountRules.mailboxList) return
	
	this.accountMailboxes = this.account.mailboxList
	const self = this, firstMsgBoxName = this.mailbox ? this.mailbox.name : null
	this.accountRules.mailboxList.forEach(function(boxRule){
		if (boxRule.name === firstMsgBoxName) return
		
		var mailbox = self.accountMailboxes.find(function(box){
			return box.name === boxRule.name
		})
		if (!mailbox) return
		
		boxRule.email = self.accountRules.email
		self.filterMailboxInLoops(boxRule, mailbox)
	})
}


/** log all message tests in separate file for debugging if shouldLogActivity == true */
const ActivityLog = (function() {
	if (!shouldLogActivity) {
		// return dummy methods if logging switched off
		const dummyFnc = function(){}
		return {log: dummyFnc,
		  logMessage: dummyFnc,
		  finish: dummyFnc
		}
	}
	
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
		const stderrFd = $.NSFileHandle.fileHandleWithStandardError.fileDescriptor
		//$.freopen(path.UTF8String, ObjC.wrap("a+").UTF8String, stderrFd)
		$.dup2(fh.fileDescriptor, stderrFd)
	} catch (e) {
		console.log(e.message)
	}
	
	/** general log function appending entry as a line to file */
	var log = function(str) {
		try {
			fh.seekToEndOfFile
			fh.writeData(ObjC.wrap(str +"\n").dataUsingEncoding($.NSUTF8StringEncoding))
		} catch (e) {
			console.log("failed writing to log file: "+ e.name +", "+ e.message)
			mail.displayDialog("failed writing to log file: "+ e.name +", "+ e.message)
			return false
		}
		return true
	}
	
	/** log given message along with run type of test */
	var logMessage = function(msg, runType) {
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
	var path = '', mutex = null, gotLock = null
	
	/** constructor creates path to mutex file */
	function RunCoordinator (resourceId) {
		path = ObjC.wrap(dir +'.'+ resourceId +'.spamfilter.lock') 
	}
	
	/** try to get lock for specified resource id and return result */
	RunCoordinator.prototype.tryLock = function() {
		mutex = $.NSDistributedLock.lockWithPath(path)

		// force unlock if older than mutexLifetime (600) sec as normal unlocking seemed to fail
		if (!mutex.lockDate.isNil()) {
			// Foundation.fw bug: lockDate set to reference date (docs say nil) if no lock present
			var nowIntvl = Math.abs(ObjC.unwrap(mutex.lockDate.timeIntervalSinceNow)),
				refIntvl = ObjC.unwrap(mutex.lockDate.timeIntervalSinceReferenceDate)
			if (nowIntvl < refIntvl && nowIntvl > mutexLifetime)
				mutex.breakLock
		}
		
		try {
			gotLock = ObjC.unwrap(mutex.tryLock)
		} catch (e) {
			console.log("mutex locking error: "+ e.message)
		}
		return gotLock
	}
	
	/** returns true if got lock else false; null if tryLock() not yet called */
	RunCoordinator.prototype.gotLock = function() {
		return gotLock
	}
	
	/** unlock existing mutex */
	RunCoordinator.prototype.unlock = function() {
		if (mutex) mutex.unlock
	}
		
	return RunCoordinator
})()

/** alert item that matched a rule; useful for enhancing rules */
function alertMatchDetails (field, item) {
	if (!shouldAlertMatchDetails) return
	mail.displayDialog(field +': '+ item, {withTitle: 'Spamfilter match details'})
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
			mail.displayDialog("B64 decode error: " + err.message);
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


// Mail JXA API wrappers
function Message(raw) {
	this._raw = raw
	this._id = null
	this._mailbox = null
}
Object.defineProperties(Message.prototype, {
	'id': {get: function(){return this._id || (this._id = this._raw.id()) }},
	'mailbox': {get: function(){
  		return this._mailbox || (this._mailbox = new Mailbox(this._raw.mailbox())) }},
	'junkMailStatus': {get: function(){return this._raw.junkMailStatus()},
  	  set: function(status){this._raw.junkMailStatus = status }},
	'readStatus': {get: function(){
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
	if (this[key]) return this[key]

	try {
		// JXA API calls 'from' header 'sender'
		if (key == 'from') this[key] = this._raw['sender']()
		else if (key == 'sender') throw new Error('')  // get real 'sender' header
		
		this[key] = this._raw[key]()
	} catch (err) {
	  	//const header = this._raw.headers.byName(key)
		const headersFiltered = this._raw.headers.whose({name: {_equals: key}}),
		  header = Array.prototype.reduce.call(headersFiltered, (acc, item) => {
		    return `${acc}\n ${item.content()}`
		  }, '')
		
		this[key] = header//.content()
	}
	
	return this[key]
}

function Mailbox(raw) {
	this._raw = raw
	this._name = null
	this._account = null
	this._messageList = null  // big array
	this._messages = null  // raw objects
	this.lazyMessageList = null
}
Object.defineProperties(Mailbox.prototype, {
	'name': {get: function(){return this._name || (this._name = this._raw.name()) }},
	'account': {get: function(){
		return this._account || (this._account = new Account(this._raw.account())) }},
	'unreadCount': {get: function(){return this._raw.unreadCount() }},
	'messageList': {get: function(){  // possibly very big array
		return this._messageList || (this._messageList = this._raw.messages()
		  .map(function(raw){return new Message(raw)})) }},
	'messageCount': {get: function(){
		if (!this._messages) this._messages = this._raw.messages()
		return this._messages.length }}
})
Mailbox.prototype.getMessageByIndex = function(idx){
	if (!this._messages) this._messages = this._raw.messages()
	if (!this.lazyMessageList) this.lazyMessageList = []
	if (!this.lazyMessageList[idx])
		this.lazyMessageList[idx] = new Message(this._messages[idx])
	return this.lazyMessageList[idx]
}
Mailbox.prototype.refreshMessageList = function(){
	this._messages = this._raw.messages()
	this._messageList = null
	this.lazyMessageList = null
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
	'id': {get: function(){return this._id || (this._id = this._raw.id()) }},
	'name': {get: function(){return this._name || (this._name = this._raw.name()) }},
	'fullName': {get: function(){
		return this._fullName || (this._fullName = this._raw.fullName()) }},
	'emailAddressList': {get: function(){
		return this._emailAddresses || (this._emailAddresses = this._raw.emailAddresses()) }},
	'mailboxList': {get: function(){
		return this._mailboxes || (this._mailboxes = this._raw.mailboxes()
		  .map(function(raw){return new Mailbox(raw)})) }}
})
