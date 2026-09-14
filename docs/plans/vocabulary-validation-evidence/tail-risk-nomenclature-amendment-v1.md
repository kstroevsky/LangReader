# Tail-risk nomenclature amendment v1

The frozen mathematical definition is unchanged. The existing
`conditionalSevereExpectedShortfall` metric may be displayed more precisely as
`conditionalTargetShortfall`:

`E[max(0, 0.98 - C_realized) | C_realized < c_severe]`.

This is target shortfall among severe misses, not excess below the severe
threshold. A distinct optional severity measure is defined as:

`conditionalThresholdExcessSeverity = E[c_severe - C_realized | C_realized < c_severe]`.

Its release role and tolerance remain null. This amendment changes no release
decision, production behavior, deferred `RISK-001` status, safeguard boundary,
or holdout authorization.
