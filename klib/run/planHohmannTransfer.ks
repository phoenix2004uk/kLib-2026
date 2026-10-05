{
	local hohmannTransfer is import("mnv/hohmannTransfer-v1").
	local prgExecuteNode is import("prg/executeNode-v1").
	local onFail is import("run/onFail").
	local REBOOT_TIMER is 60.
	local MNV_LEAD_TIME is 60.
	local TRANSFER_ENCOUNTERS_MESSAGE_PREFIX is "Transfer encounters ".
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

			if prgExecuteNode:burnDuration(mnv:deltaV:mag/2) > mnv:eta - MNV_LEAD_TIME {
				rebootTransfer("Departure burn too soon").
			}

			// Note: We don't need to `remove mnv` on failure below, as the flight-planner should be cleared by any planning stage
			if targetOrbitable:isType("Body") {
				if not transferOrbit:hasNextPatch {
					rebootTransfer("Transfer does not encounter " + targetOrbitable:name).
				}
				if transferOrbit:nextPatch:body <> targetOrbitable {
					rebootTransfer(TRANSFER_ENCOUNTERS_MESSAGE_PREFIX + transferOrbit:nextPatch:body:name).
				}
			}
			if targetOrbitable:isType("Vessel") and transferOrbit:hasNextPatch and transferOrbit:nextPatchEta < transferOrbit:period / 2 {
				// TODO: potential re-wording in case we escape current SOI to body:parent
				rebootTransfer(TRANSFER_ENCOUNTERS_MESSAGE_PREFIX + transferOrbit:nextPatch:body:name + " before target intercept").
			}
			dmsg("Encounter confirmed with " + targetOrbitable:name, true, true).

			runner:next().
		}
	).
}