// local rendezvous is import("prg/rendezvous-v1").
local hohmannTransfer is import("mnv/hohmannTransfer-v1").
local circularizeAtAp is import("mnv/circularizeAtApsis-v1"):Ap.
local approach is import("prg/approach-v1").
local dock is import("prg/dock-v1").
local exec is import("prg/executeNode-v1").
local executeNode is exec:executeNode.
local warpToNode is exec:warpToNode.

set steeringManager:maxStoppingTime to 1.
set steeringManager:pitchPid:kp to 1.5.
set steeringManager:pitchPid:ki to 0.
set steeringManager:pitchPid:kd to 0.05.
set steeringManager:pitchTs to 1.
set steeringManager:yawPid:kp to 1.5.
set steeringManager:yawPid:ki to 0.
set steeringManager:yawPid:kd to 0.05.
set steeringManager:yawTs to 1.
set steeringManager:rollControlAngleRange to 5.
set steeringManager:rollPid:kp to 2.
set steeringManager:rollPid:ki to 0.
set steeringManager:rollPid:kd to 0.
set steeringManager:rollTs to 0.7.
steeringManager:resetPids().

set terminal:width to 60.
set terminal:height to 15.
clearScreen.

dmsg("Waiting for orbit", true).
wait until status = "ORBITING".
panels on.
lights on.

set target to "".
dmsg("Select a target vessel", true).
wait until hasTarget.

dmsg("Use ABORT to rendezvous and approach", true).
local startTest is false.
on abort set startTest to true.
wait until startTest.


until not hasNode { remove nextNode. wait 0. }
local hohmannResult is hohmannTransfer(target).
if not hohmannResult:ok {
	notify("Transfer failed - shutting down").
	dmsg("Transfer planning failed: " + hohmannResult:msg, true).
	shutdown.
}

add hohmannResult:val.
notify("Executing transfer to " + target).
wait until hasNode.
warpToNode(15).
executeNode(15).


until not hasNode { remove nextNode. wait 0. }
local circularizeResult is circularizeAtAp().
if not circularizeResult:ok {
	notify("Circularization failed - shutting down").
	dmsg("Circularization planning failed: " + circularizeResult:msg, true).
	shutdown.
}

add circularizeResult:val.
notify("Executing Kerbin circularization").
wait until hasNode.
warpToNode(15).
executeNode(15).

local APPROACH_STEPS is list(
	list(1000, 20),
	list(100, 10),
	list(20, 2)
).

for approachStep in APPROACH_STEPS {
	dmsg("Approach target: " + approachStep[0] + "m @ " + approachStep[1] + "m/s", true).
	dmsg("  starting distance: " + target:distance + "m", true).
	approach(target, approachStep[0], approachStep[1]).
	dmsg("  ending distance: " + target:distance + "m", true).
	dmsg("  distance error: " + (target:distance - approachStep[0]) + "m", true).
	print "".
}
dmsg("Final separation: " + target:distance, true).


notify("Initiate docking procedure").
dock(ship:dockingports[0], target:dockingports[0], lex(
	"rollOffset", 90
)).