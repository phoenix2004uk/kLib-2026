{
	function safestage {
		local currentStage is stage:number.
		stage.
		wait until stage:ready.
		return stage:number < currentStage.
	}
	function autostage {
		local flameout is 1.
		local ignition is 0.
		local currentStage is stage:number.
		until stage:number = 0 or (not flameout and ignition) {
			set flameout to 0.
			set ignition to 0.
			for en in ship:engines {
				if en:flameout {
					set flameout to 1.
					break.
				}
				else if en:ignition {
					set ignition to 1.
				}
			}
			if flameout or not ignition safestage().
		}
		return stage:number < currentStage.
	}
	function stageUntil {
		parameter num.
		local currentStage is stage:number.
		until stage:number = 0 or stage:number <= num safestage().
		return stage:number < currentStage.
	}
	export(lex(
		"safestage", safestage@,
		"autostage", autostage@,
		"stageUntil", stageUntil@
	)).
}