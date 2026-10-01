export(lex(
	"begin", {
		parameter runner.
		dmsg("Awaiting crew egress", true).
		runner:share("crewComplement", ship:crew():length).
		runner:next().
	},
	"egress", {
		parameter runner.
		if ship:crew():length < runner:fetch("crewComplement") {
			dmsg("Crew egress detected - Awaiting crew return", true, true).
			runner:next().
		}
	},
	"ingress", {
		parameter runner.
		if ship:crew():length = runner:fetch("crewComplement") {
			dmsg("Crew ingress complete", true, true).
			runner:next().
		}
	}
)).