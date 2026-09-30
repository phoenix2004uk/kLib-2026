// Pioneer 2
// Attempt high altitude science

wait until ship:unpacked.
core:part:getmodule("kOSProcessor"):doevent("Open Terminal").
sas on.
wait 10.
stage.