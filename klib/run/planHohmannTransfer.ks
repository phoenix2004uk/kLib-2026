{
	local hohmannTransfer is import("mnv/hohmannTransfer-v1").
	local onFail is import("run/onFail").
	local REBOOT_TIMER is 60.
	local TRANSFER_ENCOUNTERS_MESSAGE_PREFIX is "Transfer encounters ".
	local ENCOUNTER_CONFIRMED_MESSAGE_PREFIX is "Encounter confirmed - Coasting to ".
	export({
			parameter targetOrbitable, runner.
			until not hasNode { remove nextNode. wait 0. }
			dmsg("Planning transfer to " + targetOrbitable:name, true, true).
			local hohmannResult is hohmannTransfer(targetOrbitable).

			// Note: `hohmannTransfer` does not have an `ApiFail` return, so just get its `val`
			local mnv is hohmannResult:val.
			add mnv.
			local rebootTransfer is {
				parameter failureMessage.
				onFail:reboot(REBOOT_TIMER, failureMessage, "Hohmann transfer").
			}.
			local transferOrbit is mnv:obt.

			// Note: We don't need to `remove mnv` on failure below, as the flight-planner should be cleared by any planning stage
			if targetOrbitable:isType("Body") {
				if not transferOrbit:hasNextPatch {
					rebootTransfer("Transfer does not encounter " + targetOrbitable:name).
				}
				if transferOrbit:nextPatch:body <> targetOrbitable {
					rebootTransfer(TRANSFER_ENCOUNTERS_MESSAGE_PREFIX + transferOrbit:nextPatch:body:name).
				}
				dmsg(ENCOUNTER_CONFIRMED_MESSAGE_PREFIX + targetOrbitable:name + " SOI", true, true).
			}
			if targetOrbitable:isType("Vessel") {
				if transferOrbit:hasNextPatch and transferOrbit:nextPatchEta < transferOrbit:period / 2 {
					// TODO: potential re-wording in case we escape current SOI to body:parent
					rebootTransfer(TRANSFER_ENCOUNTERS_MESSAGE_PREFIX + transferOrbit:nextPatch:body:name + " before target intercept").
				}
				dmsg(ENCOUNTER_CONFIRMED_MESSAGE_PREFIX + targetOrbitable:name + " intercept", true, true).
			}

			runner:next().
		}
	).
}