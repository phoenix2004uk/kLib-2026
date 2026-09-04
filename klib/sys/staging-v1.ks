{
	function safestage {
		local currentStage is stage:number.
		stage.
		wait until stage:ready.
		return stage:number < currentStage.
	}
	function autostage {
		local flameout is 1.
		local currentStage is stage:number.
		until not flameout {
			set flameout to 0.
			for en in ship:engines {
				if (en:flameout) {
					safestage().
					set flameout to 1.
					break.
				}
			}
		}
		return stage:number < currentStage.
	}
	function stageUntil {
		parameter num.
		local currentStage is stage:number.
		until stage:number = 0 or stage:number <= num { safestage(). }
		return stage:number < currentStage.
	}
	export(lex(
		"safestage", safestage@,
		"autostage", autostage@,
		"stageUntil", stageUntil@
	)).
}