# spamfilter for Apple Mail.app
This spam filter lets you easily define filter rules for each of your email accounts individually. It makes use of Mail.app's scripting interface for Applescript and JXA.
Spam messages are marked as Junk and moved to the trash folder.

## Installation
1. Download `spamfilter.scpt` and `spamfilter-rules.json`
2. Move both files to directory `~/Library/Application Scripts/com.apple.mail/`
3. Open Mail.app's preferences pane and go to "Rules"
4. Add a new rule with action "Run Applescript" choosing spamfilter.scpt

## Configuration
The configuration of the script as well as your custom rules are stored in `spamfilter-rules.json`. Edit this file using the text editor of your choice. A sample might look like this:

```javascript
{
  "shouldAlertMatchDetails": false,
  "rulesList": [
	{
	    "email": "me@example.com",
		"fromWhitelist": {"shouldTest": false, "list": []},
		"senderBlacklist": {"list": ["John Doe", "@evil.org", "GitHub"]},
		"subjectBlacklist": {"list": ["50% off", "Account suspended"]},
		"contentBlacklist": {"list": ["Dear customer"]}
	},
	{
		"email": "foo@bar.com",
		"fromWhitelist": {"shouldTest": true, "list": ["GitHub"]},
		"senderBlacklist": {"list": ["Jane Doe", "support@evil.org"]},
		"subjectBlacklist": {"list": []},
		"contentBlacklist": {"list": ["Dear customer"]}
	}
  ]
}
```

Apart from your account-specific rules the JSON object above comprises general settings like `shouldAlertMatchDetails` that always affect the filtering regardless of your rules. shouldAlertMatchDetails set to true (boolean) helps debugging false-positives by telling you which rule has matched.

The `rulesList` property contains the array of mail accounts for which you want to enable filtering. Accounts not listed there are not filtered at all. Here's a description of an account rule:
* `email` indicates the mail address of your account.
* `fromWhitelist` controls the test wether the sender contains a full name (first name and last name) or just a single word. If `shouldTest` is true, one-word names are considered as spam matches. Whitelist exceptions are likely to be necessary then, e.g., for GitHub in the foo@bar.com rule above.
* `senderBlacklist` compares the "From" header of the message with all items in the corresponding blacklist. Those items can be names,  email addresses or only string components of them.
* `subjectBlacklist` compares the "Subject" header of the message with all items in the blacklist.
* `contentBlacklist` compares the message content with all items in the blacklist. Only text content is tested. Binary data is skipped.

All comparisons with list items are case-sensitive.

## Further notes
### Automatic filtering
In addition to your own rules there are some more tests that are always performed and lead to spam matches:
* Self-addressed messages, i.e. sender = receiver, without your full name as sender
* Certain file extensions of binaries sent within messages, e.g., ".exe"
* Certain charsets, e.g., "gb2312" for Chinese
* Zero-width whitespace chars, e.g., "U+FEFF"

### Bugs in Mail.app
There seems to be a bug in Mail.app preventing the correct processing of all messages in case you receive multiple messages at once. A bug circumvention was added to spamfilter.scpt. However, if you still note unprocessed messages, you can trigger the spam filter by selecting any remaining messages and running Mail.app rules manually via `alt+cmd+L` or via its right-click context menu.

## Acknowledgments
* [JXA-Cookbook](https://github.com/JXA-Cookbook/JXA-Cookbook/wiki)
* [base64-js lib](https://github.com/beatgammit/base64-js)
* [quoted-printable](https://github.com/ronomon/quoted-printable/blob/master/index.js)
