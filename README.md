# spamfilter for Apple Mail.app on macOS
This spamfilter lets you easily define keyword-based filter rules as well as authentication policies for the senders you trust. These rules can be applied for each of your email accounts individually and cause spam messages to be marked as Junk and moved to the trash folder.
This filter makes use of Mail.app's scripting interface for Applescript and JXA.

## Installation
There are two invokation modes for the spamfilter script that impose different installation tasks. The first mode relies on Mail.app's rule infrastructure to automate handling of new incoming messages dedicated to default inboxes:
1. Download `spamfilter.zip` from [Releases](https://github.com/chsturm/spamfilter/releases)
2. Extract zip archive, open Terminal and change working directory to spamfilter directory via `cd path/to/spamfilter`
3. Run `sh install.sh` and answer the questions
4. Open Mail.app's preferences pane and go to "Rules"
5. Add a new rule with action "Run Applescript" choosing spamfilter.scpt

As rule invokation is restricted to default inboxes it might be desirable to also enable filtering on other mailboxes. This second invocation mode checks all mailboxes in a 15 minutes interval by setting up a launch agent for `launchd` daemon:
Perform the steps stated above, except step 3: Run `sh install.sh -launchagent` to set up the default launch agent or `sh install.sh -launchagent 600` to configure your own interval in seconds, e.g., 600 for 10 minutes.

## Configuration
The configuration of the script as well as your custom rules are stored in `~/Library/Application Scripts/com.apple.mail/spamfilter-rules.json`. Edit this file using the text editor of your choice. A simple sample (without sender authentication policies) might look like this:

```javascript
{
  "shouldAlertMatchDetails": false,
  "shouldLogActivity": false,
  "rulesList": [
	{
	    "email": "me@example.com",
		"fromWhitelist": {"shouldTest": false, "list": []},
		"senderBlacklist": {"similarityList": [{"selector": "GitHub", "similarityMode": "dl:2"}],
		    "list": ["John Doe", "@evil.org", "GitHub"]
		},
		"subjectBlacklist": {"list": ["50% off", "Account suspended"]},
		"contentBlacklist": {"list": ["Dear customer"]},
        "headerBlacklist": [{"name": "received", "list": ["from mta.eval.to"]},
            {"name": "content-type", "list": ["application/"]}
        ]
	},
	{
		"email": "foo@bar.com",
		"fromWhitelist": {"shouldTest": true, "list": ["GitHub"]},
		"senderBlacklist": {"list": ["Jane Doe", "support@evil.org"]},
		"subjectBlacklist": {"list": []},
		"contentBlacklist": {"list": ["Dear customer"]},
		"mailboxList": [{"name": "Another Mailbox",
		    "fromWhitelist": {"shouldTest": false, "list": []},
		    "senderBlacklist": {"list": []},
		    "subjectBlacklist": {"list": ["50% off"]},
		    "contentBlacklist": {"list": []}
		}]
	}
  ]
}
```

Apart from your account-specific rules the JSON object above comprises general settings like `shouldAlertMatchDetails` that always affect the filtering regardless of your rules. `shouldAlertMatchDetails` set to `true` (boolean) helps debugging false-positives by telling you which rule has matched. `shouldLogActivity` logs more information about each message in the file `spamfilter.log` next to your `spamfilter-rules.json`.

The `rulesList` property contains the array of mail accounts for which you want to enable filtering. Accounts not listed there, as well as already read messages, are not filtered at all. Here's a description of an account rule for its default INBOX:
* `email` indicates the mail address of your account.
* `name` [optional] indicates the usually unique account name as displayed by Mail.app in its account overview, e.g., `Example.com` or `iCloud`. This provides an alternative way to find your rules if Mail.app doesn't store any addresses for the account or has forgotten them due to bugs.
* `trustList` [optional] defines authentication policies for user-defined trusted senders identified by selector text strings that are compared to the "From" header of the message. If a selector has matched, one of its specified policies must be fulfilled, otherwise the message is classified as spam. A full description of this advanced feature is stated in the [section](#sender-authentication-policies) below.
* `fromWhitelist` controls the test whether the sender contains a full name (first name and last name) or just a single word. If `shouldTest` is `true`, one-word names are considered as spam matches. Whitelist exceptions are likely to be necessary then, e.g., for GitHub in the `foo@bar.com` rule above (case-sensitive). A whitelist match doesn't stop proceeding with remaining tests.
* `senderBlacklist` searches the "From" header of the message for all items in the corresponding blacklist. Those items can be names, email addresses or only string components of them. There are two sub-blacklists:
    * `similarityList` [optional] list of similarity objects: compares the "From" header with the `selector` string property through applying the algorithm given by property `similarityMode`. The available modes `canonical`, `dl` and `jw` are explained in the [trustList section](#properties-of-the-trustList-object) below. As this is a blacklist (in opposition to the `trustList`), a selector match leads to a spam classification here.
    * `list` literal, case-sensitive search
* `subjectBlacklist` searches the "Subject" header of the message for all items in the blacklist (case-sensitive).
* `contentBlacklist` searches the message content for all items in the blacklist (case-sensitive). Only text content is tested; binary data is skipped.
* `headerBlacklist` [optional] searches further arbitrary message headers defined by the `name` property (lower-case) for all items in the corresponding blacklist (case-sensitive).
* `mailboxList` [optional] a list of rule objects for additional mailboxes different from the default INBOX. Those rules work analogously to the ones above (from `trustList` to `headerBlacklist`), but only for a specific mailbox. Mailbox names are case-sensitive.

The list items from `trustList` to `headerBlacklist` are always processed in the order as defined above.

### Sender authentication policies
These policies help to detect phishing and spoofing through the definition of constraints that certain user-defined trusted senders must comply with. Senders are identified by selector strings searched in the whole "From" header of the message (human-readable display name + email address).  
Corresponding policies are based upon a combination of DKIM ([RFC6376](https://datatracker.ietf.org/doc/html/rfc6376), [wiki](https://en.wikipedia.org/wiki/DomainKeys_Identified_Mail)), SPF ([RFC7208](https://datatracker.ietf.org/doc/html/rfc7208), [wiki](https://en.wikipedia.org/wiki/Sender_Policy_Framework)), DMARC ([RFC7489](https://datatracker.ietf.org/doc/html/rfc7489), [wiki](https://en.wikipedia.org/wiki/DMARC)) and Authentication-Results ([RFC8601](https://datatracker.ietf.org/doc/html/rfc8601), [wiki](https://en.wikipedia.org/wiki/Email_authentication#Authentication-Results)) IETF standards to verify the original sender domain found within the "From" header as well as a configurable list of allowed sender addresses for each selector. Violation of the so found policy, i.e., an invalid sender address for the given selector or invalid headers, causes a spam match per default.

An extended sample might look like this:

```javascript
{
  "shouldAlertMatchDetails": false,
  "shouldLogActivity": false,
  "rulesList": [
    {
        "email": "me@example.com",
        "name": "Example.com",
        "trustList": {"authResultsIssuers": "example.com", "selectorMode": "relaxed", "list": [
            {"selector": ["Alice Bobman", "Bobman, Alice"], "policyList": [
                {"addresses": "alice.bobman@examplemail.com", "dkim": "self", "spf": "strict", "authResults": {"methods": "dkim,spf,dmarc"}}
            ]},
            {"selector": "Example", "policyList": [
                {"addresses": "*@example.com", "dkim": "self", "spf": "strict", "authResults": {"methods": "dkim,spf,dmarc"}},
                {"addresses": "*@examplemail.com", "onRemedy": "skip", "dkim": "self", "spf": "strict", "authResults": {"methods": "dkim,spf,dmarc"}, "proceedTests": true}
            ]}
        ]},
        "fromWhitelist": {"shouldTest": false, "list": []},
        "senderBlacklist": {"similarityList": [{"selector": "GitHub", "similarityMode": "dl:2"}],
            "list": ["John Doe", "@evil.org"]},
        "subjectBlacklist": {"list": ["50% off", "Account suspended"]},
        "contentBlacklist": {"list": ["Dear customer"]},
        "headerBlacklist": [{"name": "received", "list": ["from mta.eval.to"]},
            {"name": "content-type", "list": ["application/"]}
        ]
    },
    {
        "email": "foo@bar.com",
        "trustList": {"authResultsIssuers": "bar.com", "onViolation": "trash", "list": [
            {"selector": "GitHub", "policyList": [
                {"addresses": "*@github.com", "blueprint": "default-full", "proceedTests": true},
                {"addresses": "josh@macgithubintosh.cc, *.macgithubintosh.cc", "dmarc": "s,r;macgithubintosh.cc", "headerList": [
                    {"return-path": "@bounce.macgithubintosh.cc>", "to": "myalias@bar.com"}], "proceedTests": true}
            ]},
            {"selector": ["Microsoft", "office365support"], "similarityMode": "jw:0.64", "shouldAlertSimilarity": true, "policyList": [
                {"addresses": "*@microsoft.com, *.microsoft.com, *@office365support.com", "dmarc": "s,s", "authResults": {"methods": "dkim,spf,dmarc", "borderlineMode": "strict:softfail"}}
            ]},
            {"selector": "Jeanne Doe", "policyList": [
                {"addresses": "jeanne.doe@foo.com", "blueprint": "foo.com"}
            ]},
            {"selector": "Joe Doe", "policyList": [
                {"addresses": "joe.doe@foo.com", "blueprint": "foo.com"},
                {"addresses": "joe@doe.net", "blueprint": "default-full", "onViolation": "flag"}
            ]}
        ], "policyBlueprints": {
            "default-full": {"dkim": "self", "spf": "strict", "dmarc": "s,s", "authResults": {"methods": "dkim,spf,dmarc"}, "onViolation": "trash"},
            "foo.com": {"dkim": "self", "authResults": {"methods": "dkim,spf,dmarc"}, "onViolation": "flag"}
        }},
        "fromWhitelist": {"shouldTest": true, "list": ["GitHub"]},
        "senderBlacklist": {"list": ["Jane Doe", "support@evil.org"]},
        "subjectBlacklist": {"list": []},
        "contentBlacklist": {"list": ["Dear customer"]},
        "mailboxList": [{"name": "Another Mailbox",
            "fromWhitelist": {"shouldTest": false, "list": []},
            "senderBlacklist": {"list": []},
            "subjectBlacklist": {"list": ["50% off"]},
            "contentBlacklist": {"list": []}
        }]
    }
  ]
}
```

The next sections cover a full formal description of the `trustList` object and a straightforward explanation of the example trust lists from above.

#### Properties of the `trustList` object
* `selectorMode` [optional] one of the following options:
    1. `strict` (default) a policy of first matched selector object must be fulfilled
    2. `relaxed` also search remaining selector objects for a match to redeem violation of the first selector's policy. In this mode, a policy violation triggers the harshest user-defined `onViolation` action of all matched selectors and involved policies.
* `similarityMode` [optional] one of the following options to compare selector and "From" header:
    1. `canonical` (default) searches the complete "From" header of the message for the selector string in a canonical way, i.e., replace most non-alphanumeric characters with spaces and convert to lower-case (`Git_Hub => git hub`).
    2. `dl:x` ([Damerau-Levenshtein](https://en.wikipedia.org/wiki/Damerau–Levenshtein_distance) distance with integer threshold `x`) also searches for the canonical string, but allows for deviations in the "From" header respecting the threshold `x` for maximum admissible difference (i.e. selector matches for results less than or equal to threshold `x`). Possible edit operations are deletion, insertion and substitution of single chars as well as transposition of adjacent chars, each weighted with a cost of 1.
    3. `jw:x` ([Jaro-Winkler](https://en.wikipedia.org/wiki/Jaro–Winkler_distance) similarity with threshold `x` between 0 and 1) also searches for the canonical string, but allows for deviations in the "From" header respecting the threshold `x` for minimum admissible similarity (i.e. selector matches for results greater than or equal to threshold `x`). Note: As the "From" header is usually much longer than the selector, this implementation is adapted to stronger locality conditions than the common JW algorithm. For instance, an additional exponential penalty is subtracted for missing characters of long selector strings (slow-start penalty). In most cases, a value between 0.7 and 0.8 is an acceptable starting point.
* `onViolation` [optional] top-level definition of the action to take if a violation has occurred. One of the following options:
    1. `trash` (default) move message to trash
    2. `flag` just add junk mark and red flag to message
* `authResultsIssuers` top-level definition of RFC8601 authentication service identifiers (`authserv-id`, the first entry in "Authentication-Results" headers) within your trust zone. Typically, a comma-separated list of servers operated by your mail provider. Subdomains are automatically allowed.
* `list` list of selector objects, each containing a list of actual policies. 
    * `selector` either a text string or an array of alternative text strings that are searched in the "From" header according to the `similarityMode`. If the selector is included in the header, one of its policies in `policyList` must match too.
    * `similarityMode` [optional] overrides top-level `similarityMode` property
    * `shouldAlertSimilarity` [optional] if boolean `true`, alert details about the similarity of selector and "From" header for debugging
    * `receiverAddress` [optional] must be equal to the "To" header in order to let the selector match. Note: This property isn't part of a policy, but rather an extension to the selector, so inequality doesn't result in a violation, but skips the selector object.
    * `policyList` is searched for the first match between `addresses` property and sender address of the "From" header. The encompassing policy is chosen for the verification step. A search failure causes an immediate violation.
        * `addresses` comma-separated string of allowed sender addresses. An asterisk `*` may be added as first character, e.g., `*@github.com`, to indicate a wildcard.
        * `onRemedy` [optional] The action to take if a previous violation is redeemed (top-level `selectorMode` set to `relaxed`) and its associated selector is not the first one that matched: Either `none` (just accept message, default), `flag` (mark message as junk) or `skip` (ignore remediation and proceed with next selector/ policy). The latter values are recommended for policies that verify public mail service providers, as this prevents strangers/ attackers from exploiting the healing of a previously detected policy violation through abusing such a mail service provider.
        * `dkim` [optional] comma-separated string of allowed signer domains; a wildcard `*` as first character may be added. The shortcut value `self` is recommended instead to check for equality between signer domain of "DKIM-Signature" header and sender domain of "From" header, just like DMARC in strict mode would do. Note: No cryptographic verification is performed.
        * `spf` [optional] checks on the "Received-SPF" header to have a permissible SPF state (`pass`, `softfail`, `neutral` or `temperror`) and to match the "Return-Path" header. The states `softfail`, `temperror` and `neutral` are considered edge/ borderline cases between trusted and suspicious classification. Thus, they don't produce a violation, but nevertheless have to be dealt with according to one of the following user-defined options:
            1. `strict` edge case SPF result enacts `flag` action on the message to inform the user.
            2. `relaxed` edge case SPF result doesn't enact any action.  
        If only a specific subset of edge cases should conform to the chosen option, these SPF results can be appended to that option, e.g., `strict:temperror,neutral`. The edge cases not mentioned belong to the other option then.
        * `dmarc` [optional] comma-separated tuple string of `s` (strict, domain equality) or `r` (relaxed, domain alignment) for DKIM and SPF alignment modes as performed by DMARC standard. This encompasses both aforementioned `dkim` and `spf` verification steps as well as an alignment match with the sender domain of the "From" header. Simplification for SPF in contrast to RFC7208: Sender domain must be included in "Return-Path" or vice versa. The common organizational domain isn't determined, but can optionally be added to the `r,r` tuple by the user formatted as `;<orgaDomain>`. Note: It is sufficient for DMARC to have just one of the DKIM and SPF verifications succeed. If DKIM fails and SPF returns an edge case, `strict` mode of `spf` is always used.
        * `authResults` [optional] searches "Authentication-Results" headers for matching issuers and auth methods. Permissible method results are `pass`, `softfail`, `temperror` and `neutral`.
            * `methods` comma-separated string of auth methods that must have been passed. Currently supported: `dkim`, `spf`, `dmarc`. Note: `dkim` enforces a match between its `header.d` value (or `header.i` if `header.d` is missing/ mismatching) and the sender in "From" header of the message.
            * `borderlineMode` [optional] applies the borderline scheme of `spf` from above to all listed auth methods. Default is `strict`.
            * `issuers` [optional] overrides top-level `authResultsIssuers` property
        * `headerList` [optional] list of additional header objects having at least one object that must match. Multiple header/value properties per object are allowed.
        * `proceedTests` [optional] if boolean `true` and policy is fulfilled, proceed with remaining tests (`fromWhitelist`, etc.) just like no selector match was found (default: `false`, message gets accepted)
        * `onViolation` [optional] overrides all higher-level `onViolation` actions
        * `blueprint` [optional] references a blueprint object defined in top-level `policyBlueprints`, so that the policy doesn't have to provide its own authentication properties. If the policy specifies own properties, those will always take precedence over the blueprint.
    * `onViolation` [optional] overrides top-level `onViolation` action
* `policyBlueprints` [optional] object whose arbitrarily named properties are blueprint objects that can be referenced and reused by multiple policies. Blueprints can enclose the policy properties from `dkim` to `onViolation` listed above using the identical syntax.

Selector and policy objects are processed in the order as defined in `spamfilter-rules.json`. Thus, if two selector (in `strict` mode) or two policy objects align, it's advisable to place the more specific one before the other, e.g., selector `GitHub` before selector `Git` and policy with address `sub.example.com` before policy with address `*.example.com`.

No DNS queries are run for DKIM, SPF and DMARC, hence the respective checks above involve only plausibility tests with information extracted from the message.

If you need any help to determine the authentication methods a trusted sender seems to support, please have a look at spamfilter's command line mode described down in section [CLI mode](#cli-mode).

#### Explanation of the example `trustList` objects above
##### Account `Example.com`
As a general requirement, some policy of the matching selectors (searched throughout all selector objects) must be fulfilled. A selector match is found through simple canonical string search per default. The given trust list considers "Authentication-Results" headers exclusively created by `example.com` or its subdomains and moves spam-classified messages to trash per default.

The first trust list item provides two alternative selectors `Alice Bobman` and `Bobman, Alice`, since both are in use by Alice as display names. There is only one policy:
1. Sender address must originate from address `alice.bobman@examplemail.com`. The message must have a "DKIM-Signature" header created by the same domain and a passed "Received-SPF" header matching the "Return-Path" header. Additionally, an "Authentication-Results" header (from `example.com`, c.f. above) must list the passed methods `dkim`, `spf` and `dmarc`.

If the policy is violated, the remaining selectors are checked (top-level `selectorMode` is `relaxed`).

Selector `Example` covers all messages containing the canonicalized string `example` within their "From" header. There are two policies:
1. Sender address must originate from domain `example.com`. The same authentication properties mentioned for the first trust list item are applied to this policy, too. 
2. Sender address must originate from domain `examplemail.com` and some authentication properties must be fulfilled. We assume `examplemail.com` to be a public mail service provider. As unknown people can register arbitrary email accounts then, two problems must be faced:
    * Messages could be spam, so white- and blacklist filters (`fromWhitelist`, etc.) should always be applied (`proceedTests` set to `true`).
    * An attacker could forge an identity, e.g., `Alice Bobman <eve@examplemail.com>`, which would heal the violation of Alice's policy above (top-level `selectorMode` is `relaxed`). Thus, the policy's own `onRemedy` is set to `skip` to prevent the policy from being verified if its associated selector isn't the first one in the list that matched. So, a previous violation stays intact. Please note, that identity forgery would affect other trusted senders too if an attacker got access to a legitimate mail account and its outbound mail submission agent allowed arbitrary display names in "From" headers.

##### Account with email address `foo@bar.com`
As a general requirement, some policy of the first matching selector must be fulfilled per default, whereas a selector match is found through simple canonical string search. The given trust list considers "Authentication-Results" headers exclusively created by `bar.com` or its subdomains and moves spam-classified messages to trash.

Selector `GitHub` defines two policies:
1. Sender address must originate from domain `github.com`. As a shortcut, the authentication methods are all taken from the policy blueprint named `default-full`. It is defined as a property of the top-level `policyBlueprints` object and lists a "DKIM-Signature" header created by the sender domain (DMARC `s` mode) and a passed "Received-SPF" header matching both the "Return-Path" header and the sender domain with domain equality (DMARC `s` mode). Additionally, an "Authentication-Results" header (from `bar.com`, c.f. above) must list the passed methods `dkim`, `spf` and `dmarc`. The blueprint also requires to move violating messages to trash. If the message is trusted, i.e., no violation, still proceed with remaining tests (`fromWhitelist`, etc.).
2. Sender address must be `josh@macgithubintosh.cc` or originate from a subdomain. The message must have a "DKIM-Signature" header created by the sender domain (DMARC `s` mode for DKIM) or a passed "Received-SPF" header matching the "Return-Path" header and aligning with the organizational domain `macgithubintosh.cc` (DMARC `r` mode for SPF). The sender domain must also align with the organizational domain then. Additionally, the "Return-Path" header must include `@bounce.macgithubintosh.cc>` and the "To" header must include the user's address `myalias@bar.com`. If the message is trusted, still proceed with remaining tests.

If both policies are violated, the message is spam.

The second trust list item provides two alternative selectors `Microsoft` and `office365support`. The comparison between selectors and "From" header follows similarity mode Jaro-Winkler which requires the calculated score to be at least 0.64. This covers, e.g., the subtle substitution of I (capital i) with l (small L),  O (capital o) with 0 (zero) and S with $ as well as permutations of characters and digits. For debugging reasons, similarity details are alerted to the user.
There is only one policy:
1. Sender address must originate from domain `microsoft.com`, a subdomain or from `office365support.com`. The message must have a "DKIM-Signature" header created by the sender domain (DMARC `s` mode) or a passed "Received-SPF" header matching both the "Return-Path" header and the sender domain with domain equality (DMARC `s` mode). Additionally, an "Authentication-Results" header (from `bar.com`, c.f. above) must list the passed methods `dkim`, `spf` and `dmarc`. Edge or borderline cases (`softfail`, `temperror`) are modified to the extend that only `softfail` results are handled in the default `strict` mode, which means flagging the message as junk. both `temperror` and `neutral` results are implicitly `relaxed` then, which doesn't cause any signalling.

If this policy is violated, the message is spam.

The next two trust list items cover employees of `foo.com` with selectors `Jeanne Doe` and `Joe Doe`. Both share similar policies: The sender address must be the person's respective `foo.com` address, and, as a shortcut, the authentication methods are all taken from the policy blueprint named `foo.com`. It is defined as a property of the top-level `policyBlueprints` object and lists a "DKIM-Signature" header created by the same domain as well as an "Authentication-Results" header with methods `dkim`, `spf` and `dmarc`. The creator `bar.com` isn't explicitly arranged by the blueprint in this case (c.f. `issuers` property), but determined by the top-level `authResultsIssuers` property.  
Additionally, `Joe Doe` has another policy for his private email address `joe@doe.net`. The authentication methods are taken from blueprint `default-full`, which requires all implemented methods in `strict` mode and moves violating messages to trash. However, the policy overwrites the violation action to just flag such messages as junk.

## CLI mode
To simplify debugging as well as detecting past and unrecognized phishing events, the spamfilter script can be called in command line interface mode via the Terminal app:

`osascript "~/Library/Application Scripts/com.apple.mail/spamfilter.scpt" <cmd>`  
or via `spamfilterctl.sh` found in the zip archive: `sh spamfilterctl.sh <cmd>`

where `<cmd>` can be one of the following options:
1. `--similarity <needle> <haystack>` Applies all similarity algorithms on the provided pair of strings and prints the results.
2. `--selector-stats <selectorStr> [--similarity-mode <algo>:<threshold>] [--mailbox <account>:<mailbox>] [--period <daysPeriod>]` Prints all sender addresses and authentication statistics for messages for the given account/mailbox tuple (default: all accounts) that matched the selector string within the given period of days (default: 365; alternative date interval syntax: `<startDate>,<endDate>` both of ISO format `YYYY-MM-DD`). The similarity mode can be changed to `dl` or `jw` (default: `canonical`). The days of occurence of results other than `pass` are listed as `Error days`. Note: This command can take up some time for large mailboxes!
3. `--account-details` Prints address and mailbox details for all enabled accounts.
2. `--match-details` Temporarily sets the `shouldAlertMatchDetails` config to `true` and runs the filter process.
3. `--help` Prints a list of all available commands.

In case of execution errors, ensure that Terminal.app is allowed to control Mail.app; see System Settings -> Privacy & Security -> Automation. This permission can be revoked for the time you don't need the CLI mode.

### Examples
`--similarity GitHub "GltHUB <noreply@gitlhub.com>"`
```
Similarity results for "GitHub" and "GltHUB <noreply@gitlhub.com>"
Canonicalized forms: "github" and "glthub <noreply gitlhub com>"
Equality:			false
Damerau-Levenshtein distance:	1
Jaro-Winkler similarity:	1
```
Jaro-Winkler algorithm returns fully identical due to its prefix boost, Damerau-Levenshtein a minimum distance of 1.

`--selector-stats GitHub --mailbox Bar.com:INBOX --similarity-mode dl:2`
```
From: noreply@github.com (total count: 11)
Mailboxes: Bar.com:INBOX
Reply-To addresses: support@fake.com (2025-10-23)
DKIM: {
 self: 10 (90.9%), onlyOthers: 1 (9.1%),
 signers: github.com, fake.com
}
SPF: {pass: 11 (100.0%), softfail: 0 (0.0%), temperror: 0 (0.0%)}
DMARC: {s,s: 10 (90.9%), r,r: 10 (90.9%)}
authRes: {
 dkim: {pass: 11 (100.0%), softfail: 0 (0.0%), temperror: 0 (0.0%)}, 
 spf: {pass: 11 (100.0%), softfail: 0 (0.0%), temperror: 0 (0.0%)}, 
 dmarc: {pass: 10 (90.9%), softfail: 0 (0.0%), temperror: 0 (0.0%)},
 issuers: dkim.bar.com, spf.bar.com, dmarc.bar.com
}
Error days: 2025-10-23
```
Ten of eleven messages received in the last 365 days support all authentication methods. On 2025-10-23, a suspicious message was detected only having a DKIM signature from third party `fake.com` and the reply-to address `support@fake.com`.

`--account-details`
```
Name: Example.com
Addresses: me@example.com
Mailboxes: Archive (100), Notes (5), INBOX (4046), Drafts (1), Sent Messages (734), Deleted Messages (51), Junk (12)
```

## Build `spamfilter.scpt` file
1. Open Terminal and change working directory to extracted zip archive via `cd path/to/spamfilter`.
2. Run `sh build.sh`
3. `spamfilter.scpt` has been created and is ready for installation

## Deinstallation
Unload launch agent in Terminal:

`launchctl unload -w ~/Library/LaunchAgents/com.github.chsturm.spamfilter.plist`

Remove the following files:
- `~/Library/Application Scripts/com.apple.mail/spamfilter.scpt`
- `~/Library/Application Scripts/com.apple.mail/spamfilter-rules.json`
- `~/Library/LaunchAgents/com.github.chsturm.spamfilter.plist`
- `/usr/local/bin/spamfilterctl.sh` (if installed)

## Further notes
### Automatic filtering
In addition to your own rules there are some more tests that are always performed and lead to spam matches:
* Self-addressed messages, i.e., sender = receiver, without your full name as sender display name
* Certain file extensions of binaries sent within messages, e.g., `.exe`
* Certain charsets, e.g., `gb2312` for Chinese
* Zero-width whitespace chars, e.g., `U+FEFF`

### Bugs in Mail.app
There seems to be a bug in Mail.app preventing the correct processing of all messages in case you receive multiple messages at once. A bug circumvention was added to spamfilter.scpt. However, if you still note unprocessed messages, you can trigger the spamfilter by selecting any remaining messages and running Mail.app rules manually via `alt+cmd+L` or via its right-click context menu.
Mail only triggers its built-in rule system for new messages stored to the default INBOX, but not in other mailboxes your server may provide. Automatic filtering on all mailboxes is therefore performed as soon as a new message is received in INBOX.

## Acknowledgments
* [JXA-Cookbook](https://github.com/JXA-Cookbook/JXA-Cookbook/wiki)
* [base64-js lib](https://github.com/beatgammit/base64-js)
* [quoted-printable](https://github.com/ronomon/quoted-printable/blob/master/index.js)
