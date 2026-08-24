wait until ship:unpacked.
core:part:getmodule("kOSProcessor"):doevent("Open Terminal").
sas on.
wait 5.
stage.

// wait for SRB to deplete then fire second stage
wait until ship:maxthrust = 0.
stage.