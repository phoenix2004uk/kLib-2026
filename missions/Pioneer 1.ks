// Pioneer 1
// Leave the Launchpad
// Gather first science

wait until ship:unpacked.
core:part:getmodule("kOSProcessor"):doevent("Open Terminal").
sas on.
wait 10.
stage.