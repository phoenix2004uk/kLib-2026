// #include "kldr-stub.ks"
{
	function awaitSteering {
		wait 0.
		wait until vang(ship:facing:vector, steeringManager:target:vector) < 0.25.
	}
	export(lex(
		"awaitSteering", awaitSteering@
	)).
}