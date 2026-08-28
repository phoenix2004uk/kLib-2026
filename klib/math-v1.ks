{
	function cosh {
		parameter x.

		return (constant:e^x + constant:e^(-x)) / 2.
	}

	function acosh {
		parameter x.

		return ln(x + sqrt(x^2 - 1)).
	}

	function sinh {
		parameter x.

		return (constant:e^x - constant:e^(-x)) / 2.
	}

	function asinh {
		parameter x.

		return ln(x + sqrt(x^2 + 1)).
	}

	export(lex(
		"cosh", cosh@,
		"acosh", acosh@,
		"sinh", sinh@,
		"asinh", asinh@
	)).
}