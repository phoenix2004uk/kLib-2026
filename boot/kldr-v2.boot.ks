wait until ship:unpacked.
core:part:getmodule("kOSProcessor"):doevent("Open Terminal").
set ship:control:pilotmainthrottle to 0.
sas off.
set config:ipu to 200.
clearScreen.
{
	// =========================================================================
	// Private constants
	// =========================================================================
	local _kDebug is core:tag = "debug".
	local _kLibRoots is list(
		"0:/klib/",
		"0:/klib-nrm/",
		"0:/klib-min/"
	).
	local _kMissionRoots is list("0:/missions/").
	local _kTmpId is "0:/" + core:part:uid.
	local _kTmp is _kTmpId + ".ksm".
	local _kBestTmp is _kTmpId + "-b.ksm".
	local _kMapPath is "1:/kldr-map".

	// =========================================================================
	// Private state
	// =========================================================================
	local _kGeneration is 0.
	local _kMap is lex().
	local _kExportStack is stack().
	local _kLoadStack is stack().
	local _kLoaded is lex().
	local _kParents is lex().
	local _kChildren is lex().
	local _kRootParent is "@".

	// =========================================================================
	// Global API
	// =========================================================================
	global ApiOK is {
		parameter _kValue, _kMessage is "".

		return lex(
			"ok", true,
			"val", _kValue,
			"msg", _kMessage
		).
	}.

	global ApiFail is {
		parameter _kMessage, _kValue is false.

		return lex(
			"ok", false,
			"val", _kValue,
			"msg", _kMessage
		).
	}.

	global export is {
		parameter _kObject.

		_kExportStack:push(_kObject).
	}.

	global import is {
		parameter _kLibName.

		local _kParent is
			choose _kLoadStack:peek
			if not _kLoadStack:empty
			else _kRootParent.

		_kLink(_kParent, _kLibName).

		if _kLoaded:haskey(_kLibName) {
			return _kLoaded[_kLibName].
		}

		if _kLoadStack:contains(_kLibName) {
			print "Error! Circular import: " + _kLibName.
			shutdown.
		}

		local _kPath is _kEnsureLib(_kLibName).
		local _kExportDepth is _kExportStack:length.

		_kLoadStack:push(_kLibName).
		runPath(_kPath).
		_kLoadStack:pop().

		if _kExportStack:length <> _kExportDepth + 1 {
			print "Error! Invalid export: " + _kLibName.
			shutdown.
		}

		local _kObject is _kExportStack:pop().

		set _kLoaded[_kLibName] to _kObject.

		return _kObject.
	}.

	global purge is {
		parameter _kLibName.

		if not _kLoaded:haskey(_kLibName) {
			return ApiFail("Library not imported: " + _kLibName).
		}

		if _kParents:haskey(_kLibName) {
			local _kBlocking is _kParents[_kLibName]:copy.
			_kBlocking:remove(_kRootParent).

			if not _kBlocking:empty {
				return ApiFail("Library still has parents", _kBlocking).
			}

			_kParents[_kLibName]:remove(_kRootParent).

			if _kChildren:haskey(_kRootParent) {
				_kChildren[_kRootParent]:remove(_kLibName).
			}
		}

		local _kCount is _kDropLib(_kLibName).
		_kSaveMap().
		return ApiOK(_kCount).
	}.

	// =========================================================================
	// Boot Loader
	// =========================================================================
	function _kBoot {
		local _kMissionName is
			choose ship:name
			if _kDebug or core:tag = ""
			else core:tag.
		local _kMissionSource is "0:/missions/" + _kMissionName.
		local _kMain is "1:/main".

		if exists(_kMapPath) {
			local _kState is readJSON(_kMapPath).
			set _kGeneration to _kState[0].
			set _kMap to _kState[1].
		}

		// If the whole local library directory has been deleted,
		// discard its mappings but retain the global generation.
		if _kMap:length > 0 and not exists("1:/klib") {
			_kMap:clear().
			_kSaveMap().
		}

		if status = "PRELAUNCH" {
			if not homeConnection:isconnected {
				print "Error! No KSC Connection".
				shutdown.
			}

			if not exists(_kMissionSource + ".ks") {
				print "Error! No mission script: " + _kMissionName.
				shutdown.
			}
		}

		if _kDebug {
			if homeConnection:isconnected and exists(_kMissionSource + ".ks") {
				_kCopySource(_kMissionSource, _kMain).
			}
		}
		else if (status = "PRELAUNCH")
			or (
				not _kHasExec(_kMain)
				and homeConnection:isconnected
				and exists(_kMissionSource + ".ks")
			) {
			_kCopyBest(_kMissionName, _kMain, _kMissionRoots).
		}

		if not _kHasExec(_kMain) {
			print "Error! No local mission script".
			shutdown.
		}
	}

	// =========================================================================
	// Private implementation
	// =========================================================================
	function _kSaveMap {
		writeJSON(list(_kGeneration, _kMap), _kMapPath).
	}

	function _kHasExec {
		parameter _kBase.
		return exists(_kBase + ".ks") or exists(_kBase + ".ksm").
	}

	function _kDeleteExec {
		parameter _kBase.

		deletePath(_kBase + ".ks").
		deletePath(_kBase + ".ksm").
	}

	function _kLibPath {
		parameter _kLibName.

		return "1:/klib/" + _kLibName + "-" + abs(_kMap[_kLibName]).
	}

	function _kCopySource {
		parameter _kSrc, _kDst.

		_kDeleteExec(_kDst).
		copyPath(_kSrc + ".ks", _kDst + ".ks").
	}

	// Tests every source and its compiled equivalent on the archive.
	// Only the final smallest candidate is copied to the local volume.
	// Exactly one of dst.ks or dst.ksm remains.
	function _kCopyBest {
		parameter _kName, _kDst, _kRoots.

		local _kBestSize is -1.
		local _kBestSrc is "".
		local _kBestCompiled is false.

		deletePath(_kTmp).
		deletePath(_kBestTmp).

		for _kRoot in _kRoots {
			local _kSrc is _kRoot + _kName + ".ks".

			if exists(_kSrc) {
				local _kSize is open(_kSrc):size.

				if _kBestSize < 0 or _kSize < _kBestSize {
					set _kBestSize to _kSize.
					set _kBestSrc to _kSrc.
					set _kBestCompiled to false.
				}

				compile _kSrc to _kTmp.
				set _kSize to open(_kTmp):size.

				if _kSize < _kBestSize {
					movePath(_kTmp, _kBestTmp).
					set _kBestSize to _kSize.
					set _kBestCompiled to true.
				}
				else {
					deletePath(_kTmp).
				}
			}
		}

		if _kBestSize < 0 {
			return false.
		}

		_kDeleteExec(_kDst).

		if _kBestCompiled {
			copyPath(_kBestTmp, _kDst + ".ksm").
		}
		else {
			copyPath(_kBestSrc, _kDst + ".ks").
		}

		deletePath(_kBestTmp).

		return true.
	}

	function _kLink {
		parameter _kParent, _kChild.

		if not _kChildren:haskey(_kParent) {
			set _kChildren[_kParent] to uniqueSet().
		}
		if not _kParents:haskey(_kChild) {
			set _kParents[_kChild] to uniqueSet().
		}

		_kChildren[_kParent]:add(_kChild).
		_kParents[_kChild]:add(_kParent).
	}

	// Returns the extensionless physical local path for the library.
	function _kEnsureLib {
		parameter _kLibName.

		local _kSource is "0:/klib/" + _kLibName.
		local _kLocal is "".

		// A persisted mapping can be reused across KPU boots.
		if _kMap:haskey(_kLibName) {
			set _kLocal to _kLibPath(_kLibName).

			if _kHasExec(_kLocal) {
				// Debug refreshes the mapped file from raw source
				// when the archive is available. Since this is a
				// new boot, the pathname is not cached yet in the
				// current program context.
				if _kDebug and homeConnection:isconnected {
					if not exists(_kSource + ".ks") {
						print "Error! No library source: " + _kLibName.
						shutdown.
					}

					_kCopySource(_kSource, _kLocal).

					if _kMap[_kLibName] > 0 {
						set _kMap[_kLibName] to -_kMap[_kLibName].
						_kSaveMap().
					}
				}
				else if not _kDebug and _kMap[_kLibName] < 0 and homeConnection:isconnected {
					if _kCopyBest(_kLibName, _kLocal, _kLibRoots) {
						set _kMap[_kLibName] to -_kMap[_kLibName].
						_kSaveMap().
					}
				}

				return _kLocal.
			}

			// Mapping survived but its physical file did not.
			// Drop it and allocate a fresh generation below.
			_kMap:remove(_kLibName).
		}

		if not homeConnection:isconnected {
			print "Error! Missing library: " + _kLibName.
			print "No KSC Connection".
			shutdown.
		}

		if _kDebug and not exists(_kSource + ".ks") {
			print "Error! No library source: " + _kLibName.
			shutdown.
		}

		set _kGeneration to _kGeneration + 1.
		set _kMap[_kLibName] to
			choose -_kGeneration
			if _kDebug
			else _kGeneration.
		set _kLocal to _kLibPath(_kLibName).

		if _kDebug {
			_kCopySource(_kSource, _kLocal).
		}
		else if not _kCopyBest(_kLibName, _kLocal, _kLibRoots) {
			_kMap:remove(_kLibName).
			print "Error! No library: " + _kLibName.
			shutdown.
		}

		_kSaveMap().
		return _kLocal.
	}

	function _kDropLib {
		parameter _kLibName.

		local _kCount is 1.

		if _kChildren:haskey(_kLibName) {
			local _kDependencies is _kChildren[_kLibName]:copy.

			for _kChild in _kDependencies {
				if _kParents:haskey(_kChild) {
					_kParents[_kChild]:remove(_kLibName).

					if _kParents[_kChild]:empty {
						set _kCount to _kCount + _kDropLib(_kChild).
					}
				}
			}

			_kChildren:remove(_kLibName).
		}

		if _kParents:haskey(_kLibName) {
			_kParents:remove(_kLibName).
		}
		if _kLoaded:haskey(_kLibName) {
			_kLoaded:remove(_kLibName).
		}

		if _kMap:haskey(_kLibName) {
			_kDeleteExec(_kLibPath(_kLibName)).
			_kMap:remove(_kLibName).
		}

		return _kCount.
	}

	// =========================================================================
	// Execute boot
	// =========================================================================
	_kBoot().
}
runPath("1:/main").