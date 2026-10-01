export({
	parameter initTPU, runner.

	runner:share("Home", body:name).

	// Initialize Telemetry Processor (TPU)
	local hasTPU is false.
	if initTPU {
		for kOSProcessor in ship:modulesNamed("kOSProcessor") {
			local kOSProcessorVolume is kOSProcessor:volume.
			if (kOSProcessor:bootFileName = "" or kOSProcessor:bootFileName = "None") and kOSProcessorVolume:files:length = 0 {
				set kOSProcessor:tag to "TPU".
				set kOSProcessorVolume:name to "tpu" + kOSProcessor:part:uid.
				set hasTPU to true.

				copyPath(
					"1:/" + core:bootFileName,
					kOSProcessorVolume:name + ":/" + core:bootFileName
				).
				set kOSProcessor:bootFileName to core:bootFileName.

				runner:share("TPUid", kOSProcessor:part:uid).
				runner:share("TPUvolume", kOSProcessorVolume:name).

				kOSProcessor:deactivate().
				kOSProcessor:activate().
				break.
				// To get the TPU processor later:
				//	if runner:fetch("hasTPU") {
				//		local TPU is processor(volume(runner:fetch("TPUvolume"))).
				//		local tpuConnection is TPU:connection.
				//	}
			}
		}
	}
	runner:share("hasTPU", hasTPU).

	notify("Launch in 3 seconds").
	lights on.
	wait 3.
	runner:next().
}).