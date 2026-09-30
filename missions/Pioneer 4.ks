// Pioneer 4
// Attempt #2 for a sub-orbital flight

lock steering to heading(0, 90).

wait 10.
stage.
wait until stage:ready.

wait 2.
lock steering to heading(0, 88).

wait until availableThrust = 0.
stage.
wait until stage:ready.
lock steering to heading(0, 80).

wait until availableThrust = 0.
stage.
lock steering to prograde.

wait until verticalSpeed < 0.
lock steering to srfRetrograde.
wait until 0.