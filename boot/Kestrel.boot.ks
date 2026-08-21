// Generic boot loader for vessels named Mission-Number e.g. Kestrel-01

set name to ship:name.
set parts to name:split("-").
set mission to parts[0].
set number to parts[1]:tonumber(0).

until number < 1 {
	set num to number:tostring.
	if num:length < 2 {
		set num to "0" + num.
	}
	set filename to mission + "-" + num + ".ks".

	if (volume(0):exists(filename)) {
		print "Booting " + filename.
		runpath("0:/" + filename).
		break.
	}

	set number to number - 1.
}

if number < 1 {
	print "Error: No mission script found".
}