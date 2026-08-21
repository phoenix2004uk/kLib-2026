local mission is ship:name.
print mission + " bootloader v1.0".
wait until ship:unpacked.
core:part:getmodule("kOSProcessor"):doevent("Open Terminal").
sas off.

local deps is list(
	"steering-v1",
	"staging-v1",
	"ascent-v1",
	"orbitals-v1",
	"seekNode-v1",
	"executeNode-v1",
	"changeApsis-v1"
).
if homeConnection:isconnected {
	for file in deps compile "0:/common/" + file + ".ks" to "1:/" + file + ".ksm".
	compile "0:/missions/" + mission + ".ks" to "1:/" + mission + ".ksm".
}
for file in deps runOncePath("1:/" + file).
runOncePath("1:/" + mission + ".ksm").