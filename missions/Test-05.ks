local rt is import("sys/remoteTech-v1").

local allAntennae is rt:getAll().
local allDish is rt:getAllDish().
local allOmni is rt:getAllOmni().


clearScreen.
dmsg("Show all status/energy", true).
for antenna in allAntennae {
	dmsg("  " + antenna:title + " -> " + antenna:status() + " / " + antenna:energy(), true).
}
print "Press any key to continue".
terminal:input:getchar().


clearScreen.
dmsg("Enabling all dishes", true).
for antenna in allDish {
	dmsg("  " + antenna:title + " [" + antenna:status() + "] -> " + antenna:enable(), true).
}
print "Press any key to continue".
terminal:input:getchar().


clearScreen.
dmsg("Disabling all omni", true).
for antenna in allOmni {
	dmsg("  " + antenna:title + " [" + antenna:status() + "] -> " + antenna:disable(), true).
}
print "Press any key to continue".
terminal:input:getchar().


clearScreen.
dmsg("Target all dish to Mun", true).
for antenna in allDish {
	dmsg("  " + antenna:title + " -> " + antenna:setTarget(Mun), true).
}
print "Press any key to continue".
terminal:input:getchar().


clearScreen.
dmsg("Target 1st dish to Minmus", true).
dmsg("  " + allDish[0]:title + " -> " + allDish[0]:setTarget(Minmus), true).
print "Press any key to continue".
terminal:input:getchar().


clearScreen.
dmsg("Disble 1st dish then target Duna", true).
dmsg("  " + allDish[0]:title + " [" + allDish[0]:status() + "] -> " + allDish[0]:disable(), true).
dmsg("  " + allDish[0]:title + " [" + allDish[0]:status() + "] -> " + allDish[0]:setTarget(Duna), true).
print "Press any key to continue".
terminal:input:getchar().


clearScreen.
dmsg("Disable 1st dish (already disabled)", true).
dmsg("  " + allDish[0]:title + " [" + allDish[0]:status() + "] -> " + allDish[0]:disable(), true).
print "Press any key to continue".
terminal:input:getchar().


clearScreen.
dmsg("Enable all omni", true).
for antenna in allOmni {
	dmsg("  " + antenna:title + " [" + antenna:status() + "] -> " + antenna:enable(), true).
}
print "Press any key to continue".
terminal:input:getchar().


clearScreen.
dmsg("Stale part staging test...", true).
local reflectron is rt:getAntennae("Reflectron GX-128")[0].
dmsg("Before staging: " + reflectron:available(), true).
wait 1.
stage.
wait 1.
dmsg("Available: " + reflectron:available(), true).
dmsg("Energy: " + reflectron:energy(), true).
dmsg("Status: " + reflectron:status(), true).
dmsg("Enable: " + reflectron:enable(), true).
dmsg("Disable: " + reflectron:disable(), true).
print "Press any key to continue".
terminal:input:getchar().


clearScreen.
dmsg("Show all status/energy", true).
for antenna in allAntennae {
	dmsg("  " + antenna:title + " -> " + antenna:status() + " / " + antenna:energy(), true).
}
print "Press any key to continue".
terminal:input:getchar().


clearScreen.
dmsg("Enable all antennae", true).
for antenna in allAntennae {
	dmsg("  " + antenna:title + " [" + antenna:status() + "] -> " + antenna:enable(), true).
}
print "Press any key to continue".
terminal:input:getchar().


clearScreen.
dmsg("Test complete", true).
shutdown.