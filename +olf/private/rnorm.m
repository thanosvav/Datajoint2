function [traces,out] = rnorm(traces,fps,traceOpts) %#ok<*INUSD>

traces = traces(:,:,1)./traces(:,:,2);

if nargout>1
    out = [];
end