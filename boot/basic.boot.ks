wait until ship:unpacked.
core:part:getmodule("kOSProcessor"):doevent("Open Terminal").
sas off.

// Steering Manager tuning
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

if status = "PRELAUNCH" {
	copyPath("0:/missions/" + ship:name + ".ks", "1:/main.ks").
}
runPath("1:/main.ks").