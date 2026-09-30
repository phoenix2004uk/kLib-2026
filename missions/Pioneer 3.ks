// Pioneer 3
// Attempt a sub-orbital flight

lock steering to heading(0, 90).

wait 10.
stage.
wait until stage:ready.

wait until availableThrust = 0.
stage.
wait until stage:ready.
lock steering to heading(0, 80).

wait until availableThrust = 0.
stage.
unlock steering.