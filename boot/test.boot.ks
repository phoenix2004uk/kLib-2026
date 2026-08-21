wait until ship:unpacked.
core:part:getmodule("kOSProcessor"):doevent("Open Terminal").
sas off.
local mission is ship:name.

local deps is list(
	"printLn-v1",
	"math-v1",
	"orbitalMechanics-v1",
	"orbitalParameters-v1",
	"staging-v1",
	"steering-v1",
	"ascent-v2",
	"executeNode-v1",
	"circularizeAtAp-v1"
).
if homeConnection:isconnected {
	for file in deps compile "0:/lib-v1/" + file + ".ks" to "1:/" + file + ".ksm".
	compile "0:/missions/" + mission + ".ks" to "1:/" + mission + ".ksm".
}
for file in deps runOncePath("1:/" + file).
runOncePath("1:/" + mission + ".ksm").