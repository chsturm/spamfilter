#!/bin/sh

osacompile -l JavaScript -o spamfilter.scpt spamfilter.applescript

cd spamfilterctl_src
xcodebuild -target spamfilterctl -scheme spamfilterctl -configuration Debug build &&
codesign --sign - --force --preserve-metadata=entitlements,requirements,flags,runtime "./../spamfilterctl"
