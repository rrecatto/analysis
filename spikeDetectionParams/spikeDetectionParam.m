classdef spikeDetectionParam
    
    properties (GetAccess=public, SetAccess=private)
        paramName = 'standard';
    end
    
    methods
        function out = spikeDetectionParam(paramName)
            out.paramName = paramName;
        end
        
        function par = setupAndValidateParams(par,varargin)
            disp('doing nothing here');
        end
    end
end