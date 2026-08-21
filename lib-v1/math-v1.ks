global function cosh {
	parameter x.

	return (constant:e^x + constant:e^(-x)) / 2.
}

global function acosh {
	parameter x.

	return ln(x + sqrt(x^2 - 1)).
}

global function sinh {
	parameter x.

	return (constant:e^x - constant:e^(-x)) / 2.
}