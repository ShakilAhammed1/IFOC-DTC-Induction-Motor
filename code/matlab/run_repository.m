function run_repository(mode)
% Convenience entry point; original research scripts/models are unchanged.
% Default is schema preflight only, with no simulation.
if nargin==0, mode='preflight'; end
mode=lower(char(mode));
assert(ismember(mode,{'preflight','pilot','envelope','switching','refine','dtc_refine'}), ...
    'Use preflight, pilot, envelope, switching, refine, or dtc_refine.');
root=fileparts(mfilename('fullpath'));
oldDir=pwd; oldPath=path;
oldCfg=Simulink.fileGenControl('getConfig');
cleanup=onCleanup(@()restoreSession(oldDir,oldPath,oldCfg)); %#ok<NASGU>
cd(root);addpath(root,'-begin');
assert(strcmpi(which('run_stage12'),fullfile(root,'run_stage12.m')), ...
    'Another run_stage12.m is shadowing this copy.');
assert(strcmpi(which('run_stage12_dtc_check'),fullfile(root,'run_stage12_dtc_check.m')), ...
    'Another run_stage12_dtc_check.m is shadowing this copy.');
build=fullfile(tempdir,'S12_repo_build');
Simulink.fileGenControl('set','CacheFolder',fullfile(build,'cache'), ...
    'CodeGenFolder',fullfile(build,'code'),'createDir',true);
fprintf('Repository MATLAB folder: %s\n',root);
fprintf('Temporary build root: %s\n',build);
if strcmp(mode,'dtc_refine')
    run_stage12_dtc_check;
else
    run_stage12(mode);
end
if strcmp(mode,'preflight')
    fprintf('Repository preflight completed; no simulation or compilation was run.\n');
end
end
function restoreSession(oldDir,oldPath,oldCfg)
try
    Simulink.fileGenControl('setConfig','config',oldCfg);
catch ME
    warning('IFOC_DTC:RestoreConfig','Could not restore file generation settings: %s',ME.message);
end
cd(oldDir);path(oldPath);
end
