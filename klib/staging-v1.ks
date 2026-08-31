{
	function safestage {
		stage.
		wait until stage:ready.
	}
	function autostage {
		local flameout is 1.
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
	}
	function stageUntil {
		parameter num.
		lock throttle to 0.
		until stage:number = 0 or stage:number <= num { safestage(). }
		wait 0.1.
	}
	export(lex(
		"safestage", safestage@,
		"autostage", autostage@,
		"stageUntil", stageUntil@
	)).
}