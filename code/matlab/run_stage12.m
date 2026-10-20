function run_stage12(mode)
% Stage12 v1.0: independent resistance estimates and switching activity tests.
% Default: three IFOC pilot cases. Sources are never edited in place.
% MATLAB R2025b/Simscape Electrical required. Not runtime-tested by author.
if nargin==0,mode='pilot';end
mode=lower(char(mode));
assert(ismember(mode,{'preflight','pilot','envelope','switching','refine'}),'Unknown mode.');
root=fileparts(mfilename('fullpath'));folder=fullfile(root,'Stage12_Output_v1');
if ~isfolder(folder),mkdir(folder);end
srcF=fullfile(root,'source_models','IFOC_rotorR150_20261016_232021_968.slx');
srcD=fullfile(root,'source_models','DTC_step625_20261016_164342_084.slx');
assert(isfile(srcF)&&isfile(srcD),'Extract the complete ZIP, including source_models.');
loaded=find_system('Type','block_diagram');
for k=1:numel(loaded)
 if strcmp(get_param(loaded{k},'BlockDiagramType'),'model')
  assert(strcmp(get_param(loaded{k},'SimulationStatus'),'stopped'),'Finish or stop the current simulation first.');
 end
end
diary(fullfile(folder,'LOG.txt'));dg=onCleanup(@()diary('off')); %#ok<NASGU>
fprintf('\nSTAGE12 v1.0 | %s | %s\n',mode,char(datetime('now')));
try
 P=preflight(srcF,srcD,folder);
 if strcmp(mode,'preflight'),fprintf('PREFLIGHT PASSED. No simulation executed.\n');return;end
 pilot=[spec('IFOC',1,1,1,1600,1),spec('IFOC',1.5,1,1,1600,1),spec('IFOC',1.5,1.5,1,1600,1)];
 if strcmp(mode,'pilot')
  for j=1:numel(pilot)
   [S,~]=one(pilot(j),P,srcF,srcD,folder);
   if j==1,baselineGate(S);end
  end
 elseif strcmp(mode,'envelope')
  requirePilot(folder);cases=pilot([]);
  for loadpu=[1 .5]
   for r=[1 1.1 1.25 1.375 1.5]
    for c={'IFOC','DTC'},cases(end+1)=spec(c{1},r,1,loadpu,1600,1);end %#ok<AGROW>
   end
   cases(end+1)=spec('IFOC',1.5,1.5,loadpu,1600,1); %#ok<AGROW>
  end
  for j=1:numel(cases),one(cases(j),P,srcF,srcD,folder);end
 elseif strcmp(mode,'switching')
  requirePilot(folder);
  % Calibration uses only measured gate activity at nominal full load.
  [F,~]=one(spec('IFOC',1,1,1,1600,1),P,srcF,srcD,folder);
  factors=[1 .6 .35 .2 .1 .05 .025 .01];rows=struct('BandFactor',{},'GateRate_Hz',{},'RelativeGap',{},'SettledScreen',{});
  for b=factors
   [S,~]=one(spec('DTC',1,1,1,1600,b),P,srcF,srcD,folder);
   rows(end+1)=struct('BandFactor',b,'GateRate_Hz',S.MeanGateTurnOnRate_Hz, ...
    'RelativeGap',abs(S.MeanGateTurnOnRate_Hz/F.MeanGateTurnOnRate_Hz-1), ...
    'SettledScreen',S.SettledScreen); %#ok<AGROW>
  end
  writetable(struct2table(rows),fullfile(folder,'SWITCHING_CALIBRATION.csv'));
  gaps=[rows.RelativeGap];gaps(~[rows.SettledScreen])=Inf;[gap,ix]=min(gaps);
  assert(isfinite(gap),'No settled DTC calibration candidate; inspect raw records.');
  selectedBand=factors(ix);matchedAtNominal=gap<=.05;targetRate=F.MeanGateTurnOnRate_Hz;
  save(fullfile(folder,'switching_selection.mat'),'selectedBand','matchedAtNominal','targetRate','gap');
  fprintf('Selected band factor %.4g, nominal activity gap %.2f%%.\n',selectedBand,100*gap);
  if ~matchedAtNominal
   fprintf('NOT MATCHED within 5%%. Keep all candidates; do not label equal-activity results.\n');
   return
  end
  % Held-out operating conditions. Freeze selected bands, do not recalibrate.
  for pair=[1600 .5;900 1;1600 1]'
   speed=pair(1);loadpu=pair(2);r=1;
   if speed==1600&&loadpu==1,r=1.5;end
   one(spec('DTC',r,1,loadpu,speed,selectedBand),P,srcF,srcD,folder);
   one(spec('IFOC',r,1,loadpu,speed,1),P,srcF,srcD,folder);
  end
 elseif strcmp(mode,'refine')
  requirePilot(folder);
  for j=2:3
   c=pilot(j);c.Step_s=.3125e-6;c.ID=[c.ID '_h3125'];one(c,P,srcF,srcD,folder);
  end
 end
 rebuild(folder);
 fprintf('\nBATCH FINISHED. No new THD claims have been computed here.\n');
 fprintf('Send SUMMARY.csv, LOG.txt and PREFLIGHT.txt from:\n%s\n',folder);
 fprintf('Keep all *_data.mat files for full spectral analysis.\n');
catch ME
 fid=fopen(fullfile(folder,'ERROR_REPORT.txt'),'w');
 if fid~=-1,fprintf(fid,'%s',getReport(ME,'extended','hyperlinks','off'));fclose(fid);end
 fprintf(2,'STOPPED: %s\nCompleted cases are retained. Send LOG.txt and ERROR_REPORT.txt.\n',ME.message);
 rethrow(ME)
end
end
function c=spec(ctrl,r,est,loadpu,speed,band)
c=struct('Protocol','Stage12_v1.0','Controller',ctrl,'RotorFactor',r,'EstimateFactor',est, ...
 'Load_pu',loadpu,'Speed_rpm',speed,'BandFactor',band,'Step_s',.625e-6, ...
 'Stop_s',3.5,'WindowStart_s',3,'Timeout_s',2700);
if speed==900,c.Stop_s=4.5;c.WindowStart_s=3.5;end
c.ID=sprintf('%s_R%04d_E%04d_L%03d_N%d_B%04d',ctrl,round(r*1000),round(est*1000),round(loadpu*100),speed,round(band*1000));
end
function P=preflight(srcF,srcD,folder)
keys={'Pn','Vn','fn','p','Rss','Rrr','Xls','Xlr','Xm','H','F','Vdc','Tbase','rpmBase','Tsc'};
P=struct;fid=fopen(fullfile(folder,'PREFLIGHT.txt'),'w');assert(fid~=-1);fc=onCleanup(@()fclose(fid)); %#ok<NASGU>
for j=1:2
 if j==1,src=srcF;else,src=srcD;end
 [m,path]=clone(src,folder,'preflight');guard=onCleanup(@()closeSafe(m)); %#ok<NASGU>
 ws=get_param(m,'ModelWorkspace');
 for k=1:numel(keys)
  key=keys{k};v=evalin(ws,key);assert(isnumeric(v)&&isscalar(v)&&isfinite(v));
  if j==1,P.(key)=v;else,assert(abs(v-P.(key))<1e-10*max(1,abs(v)),'Plant workspace mismatch: %s',key);end
 end
 assert(abs(str2double(get_param(m,'FixedStep'))-.625e-6)<1e-14,'Source step changed.');
 assert(abs(P.Rrr-.020659)<1e-12&&abs(P.Vdc-750)<1e-9&&abs(P.Tsc-50e-6)<1e-12,'Unexpected source values.');
 for b={'ASM',' Reference speed','Tbase',sprintf('Solver\nConfiguration'),'ResearchRecording/Save_Iabc','ResearchRecording/Save_gates'}
  assert(getSimulinkBlockHandle([m '/' b{1}])>0,'Missing block: %s',b{1});
 end
 if j==1
  b=[m '/Control/FOC'];P.RrEstimate_pu=str2double(get_param(b,'Rr'));
  Z=P.Vn^2/P.Pn;assert(abs(P.RrEstimate_pu-P.Rrr/Z)<1e-10,'IFOC estimate is not nominal.');
  assert(abs(str2double(get_param(b,'fsw'))-1000)<1e-8,'IFOC carrier changed.');
  assert(abs(str2double(get_param(b,'iq_max'))-2)<1e-10,'IFOC current limit changed.');
  delays={'CurrentDelay','SpeedDelay'};
 else
  b=[m '/Control/ Direct Torque Control'];
  assert(abs(str2double(get_param(b,'THystBand'))-100)<1e-10);
  assert(abs(str2double(get_param(b,'FluxHystBand'))-.2)<1e-10);
  delays={'Unit Delay1','Unit Delay4','Unit Delay5'};
 end
 for k=1:numel(delays)
  assert(abs(str2double(get_param([m '/Control/' delays{k}],'SampleTime'))-5e-6)<1e-12,'Feedback delay changed.');
 end
 fprintf(fid,'Source: %s\nCopy: %s\n',src,path);
 fprintf(fid,'Plant Rrd source=%s (overridden per case); workspace nominal Rrr=%.12g Ohm\n',get_param([m '/ASM'],'Rrd'),P.Rrr);
 names=get_param(b,'MaskNames');vals=get_param(b,'MaskValues');
 for k=1:numel(names),fprintf(fid,'%s=%s\n',names{k},vals{k});end
 closeSafe(m);clear guard
end
fprintf(fid,'PASS: schemas and common workspace parameters checked. Compilation/runtime validation occurs in pilot.\n');
save(fullfile(folder,'PREFLIGHT.mat'),'P');
end
function [m,path]=clone(src,folder,label)
[~,token]=fileparts(tempname);m=['S12_' label '_' token];
path=fullfile(folder,[m '.slx']);copyfile(src,path);load_system(path);
assert(strcmpi(get_param(m,'FileName'),path),'Unexpected loaded file; possible model shadowing.');
end
function closeSafe(m)
if bdIsLoaded(m),close_system(m,0);end
end
function baselineGate(S)
% Broad repeatability screen, not scientific equivalence or a tuning target.
assert(S.SettledScreen&&S.SpeedMAE_rpm<1&& ...
 abs(S.TorqueRMS_Nm/48.7665641392-1)<.05&& ...
 abs(S.MeanPhaseCurrentRMS_A/191.7892686973-1)<.03&& ...
 abs(S.MeanGateTurnOnRate_Hz/1006-1)<.03, ...
 'Nominal repeatability screen failed. Inspect pilot before new comparisons.');
end
function requirePilot(folder)
c=spec('IFOC',1,1,1,1600,1);z=load(fullfile(folder,[c.ID '_data.mat']),'S','completed');
assert(z.completed);baselineGate(z.S);
for e=[1 1.5]
 c=spec('IFOC',1.5,e,1,1600,1);z=load(fullfile(folder,[c.ID '_data.mat']),'completed');assert(z.completed);
end
end
function [S,signals]=one(c,P,srcF,srcD,folder)
target=fullfile(folder,[c.ID '_data.mat']);
if isfile(target)
 z=load(target,'settings','completed','S');
 if isfield(z,'completed')&&z.completed&&isfield(z,'S')&&isequaln(z.settings,c)
  S=z.S;signals=struct;fprintf('REUSE %s\n',c.ID);return
 end
 [~,tok]=fileparts(tempname);movefile(target,fullfile(folder,[c.ID '_partial_' tok '.mat']));
end
if strcmp(c.Controller,'IFOC'),src=srcF;else,src=srcD;end
[m,modelPath]=clone(src,folder,c.Controller);clean=onCleanup(@()closeSafe(m)); %#ok<NASGU>
ws=get_param(m,'ModelWorkspace');assignin(ws,'Ts',c.Step_s);
set_param(m,'FixedStep',num(c.Step_s),'StopTime',num(c.Stop_s),'SignalLogging','off');
set_param([m sprintf('/Solver\nConfiguration')],'LocalSolverSampleTime',num(c.Step_s), ...
 'DoFixedCost','on','MaxNonlinIter','10','MaxModeIter','4');
set_param([m '/ Reference speed'],'Time','0.4','Before','0','After',num(c.Speed_rpm));
set_param([m '/Tbase'],'Time','1.6','Before','0','After',num(c.Load_pu));
set_param([m '/ASM'],'Rrd',num(P.Rrr*c.RotorFactor));
if strcmp(c.Controller,'IFOC')
 set_param([m '/Control/FOC'],'Ts',num(c.Step_s),'Rr',num(P.RrEstimate_pu*c.EstimateFactor));
else
 set_param([m '/Control/ Direct Torque Control'],'THystBand',num(100*c.BandFactor),'FluxHystBand',num(.2*c.BandFactor));
end
% Keep high-rate electrical signals un-decimated, final interval + 0.1 s.
for n={'Iabc','Vabc','Te','gates'}
 set_param([m '/ResearchRecording/Save_' n{1}], ...
  'MaxDataPoints',num(ceil((c.Stop_s-c.WindowStart_s+.1)/c.Step_s)+3),'Decimation','1');
end
% Existing diagnostic recorders only: control-rate logging, no feedback change.
if strcmp(c.Controller,'IFOC')
 logs=find_system([m '/Control/FOC'],'LookUnderMasks','all','FollowLinks','on','BlockType','ToWorkspace');
 for k=1:numel(logs)
  set_param(logs{k},'SampleTime',num(P.Tsc),'MaxDataPoints','inf','Decimation','1');
 end
end
save_system(m,modelPath);
settings=c;parameters=P;completed=false;
save(fullfile(folder,[c.ID '_settings.mat']),'settings','parameters','modelPath');
fprintf('\nRUN %s | target %.2f s | step %.4f us | timeout 45 min\n',c.ID,c.Stop_s,c.Step_s*1e6);
fprintf('Keep laptop awake, connected to power and lid open. Ctrl+C interrupts.\n');
clock=tic;
out=sim(m,'Timeout',c.Timeout_s,'SaveTime','on','TimeSaveName','tout','ReturnWorkspaceOutputs','on');
wall=toc(clock);t=out.get('tout');
execution=out.SimulationMetadata.ExecutionInfo;timing=out.SimulationMetadata.TimingInfo;
completed=~isempty(t)&&t(end)>=c.Stop_s-1e-9&&strcmp(char(execution.StopEvent),'ReachedStopTime');
signals=struct;names=out.who;
for k=1:numel(names)
 v=out.get(names{k});if ~isa(v,'timeseries'),continue;end
 tt=double(v.Time(:));xx=double(v.Data);
 if ~v.IsTimeFirst,xx=permute(xx,[ndims(xx) 1:ndims(xx)-1]);end
 signals.(names{k})=struct('time_s',tt,'values',reshape(xx,numel(tt),[]));
end
save(target,'settings','parameters','signals','completed','execution','timing','wall','modelPath','-v7.3');
assert(completed,'Run incomplete; partial data saved: %s',c.ID);
for n={'ue_Iabc','ue_Vabc','ue_Te','ue_gates','ue_ref','ue_speed'}
 assert(isfield(signals,n{1}),'Missing output %s',n{1});q=signals.(n{1});
 assert(all(isfinite(q.values),'all')&&all(diff(q.time_s)>0),'Nonfinite data or nonmonotonic time: %s',n{1});
 assert(q.time_s(1)<=c.WindowStart_s&&q.time_s(end)>=c.Stop_s-2*P.Tsc,'Incomplete analysis window: %s',n{1});
end
N=struct;for n={'Iabc','Vabc','Te','gates'},N.(n{1})=signals.(['ue_' n{1}]);end
O=struct('t',signals.ue_speed.time_s,'speed',signals.ue_speed.values, ...
 'ref',interp1(signals.ue_ref.time_s,signals.ue_ref.values,signals.ue_speed.time_s,'previous','extrap'));
[S,detail]=measure(N,O,c.ID,c.Step_s,P,[c.WindowStart_s c.Stop_s]);
S.Controller=c.Controller;S.RotorFactor=c.RotorFactor;S.EstimateFactor=c.EstimateFactor;
S.Load_pu=c.Load_pu;S.SpeedReference_rpm=c.Speed_rpm;S.BandFactor=c.BandFactor;S.Runtime_s=wall;
S.IqLimitFraction=NaN;S.Voltage99Fraction=NaN;
if isfield(signals,'s2_iq_ref')
 q=signals.s2_iq_ref;a=q.time_s>=c.WindowStart_s&q.time_s<c.Stop_s;
 S.IqLimitFraction=mean(abs(q.values(a,1))>=1.98);
end
if isfield(signals,'s2_vdq_limited')&&isfield(signals,'s2_voltage_limit')
 q=signals.s2_vdq_limited;v=signals.s2_voltage_limit;
 lim=interp1(v.time_s,v.values(:,1),q.time_s,'previous','extrap');
 a=q.time_s>=c.WindowStart_s&q.time_s<c.Stop_s;
 assert(size(q.values,2)==2,'Expected dq voltage vector.');
 utilization=sqrt(sum(q.values.^2,2))./max(abs(lim),eps);
 S.Voltage99Fraction=mean(utilization(a)>=.99);
end
save(target,'S','detail','-append');rebuild(folder);
try,plotCase(signals,c,folder);catch ME,fprintf('Plot warning: %s\n',ME.message);end
fprintf('DONE %.1f min | settled=%d | speed MAE %.4g rpm | torque std %.4g Nm | gate %.4g Hz\n', ...
 wall/60,S.SettledScreen,S.SpeedMAE_rpm,S.TorqueRMS_Nm,S.MeanGateTurnOnRate_Hz);
end
function s=num(v),s=sprintf('%.17g',v);end
function rebuild(folder)
f=dir(fullfile(folder,'*_data.mat'));a=struct([]);
for k=1:numel(f)
 z=load(fullfile(f(k).folder,f(k).name),'S','completed');
 if isfield(z,'S')&&isfield(z,'completed')&&z.completed,a=[a z.S];end %#ok<AGROW>
end
if ~isempty(a),writetable(struct2table(a),fullfile(folder,'SUMMARY.csv'));end
end

function [S,D]=measure(N,O,id,h,P,window)
lo=window(1); hi=window(2); mid=(lo+hi)/2;
t=N.Te.time_s; q=N.Te.values;
a=t>=lo & t<hi; a1=t>=lo & t<mid; a2=t>=mid & t<hi;
qMean=mean(q(a)); qRms=std(q(a),1);
D=struct('torqueMeanDrift_Nm',mean(q(a2))-mean(q(a1)));
t=N.Iabc.time_s; i=N.Iabc.values; a=t>=lo & t<hi;
a1=t>=lo & t<mid; a2=t>=mid & t<hi;
D.phaseRMS_A=sqrt(mean(i(a,:).^2,1));
r1=sqrt(mean(i(a1,:).^2,1)); r2=sqrt(mean(i(a2,:).^2,1));
D.phaseRMSDrift_pct=100*abs(r2-r1)./max(r1,eps);
% Aggregate three-phase energy reduces arbitrary half-window phase bias.
agg1=sqrt(mean(sum(i(a1,:).^2,2)/3));
agg2=sqrt(mean(sum(i(a2,:).^2,2)/3));
D.currentRMSDrift_pct=100*abs(agg2-agg1)/max(agg1,eps);
peak=max(abs(i(a,:)),[],'all');
t=N.gates.time_s; g=double(N.gates.values);
assert(size(g,2)==6,'Expected six inverter gates.');
% Difference is evaluated using preceding retained sample; no boundary edge loss.
rises=diff(g,1,1)>0; eventTimes=t(2:end); a=eventTimes>=lo & eventTimes<hi;
D.turnOnRates_Hz=sum(rises(a,:),1)/(hi-lo);
a=O.t>=lo & O.t<hi; a1=O.t>=lo & O.t<mid; a2=O.t>=mid & O.t<hi;
D.speedMeanDrift_rpm=mean(O.speed(a2))-mean(O.speed(a1));
err=O.speed-O.ref; after=O.t>=1.6;
speedRef=median(O.ref(a));
lastOutside=find(after & abs(err)>0.02*speedRef,1,'last');
if isempty(lastOutside), recovery=0;
elseif lastOutside==numel(O.t), recovery=NaN;
else, recovery=O.t(lastOutside+1)-1.6; end
settled=100*abs(D.torqueMeanDrift_Nm)/P.Tbase<1 && ...
    abs(D.speedMeanDrift_rpm)<1 && D.currentRMSDrift_pct<1 && mean(abs(err(a)))<.01*speedRef;
S=struct('Case',id,'Step_us',h*1e6,'SpeedMAE_rpm',mean(abs(err(a))), ...
    'MeanTorque_Nm',qMean,'TorqueRMS_Nm',qRms,'TorqueRMS_pct_base',100*qRms/P.Tbase, ...
    'TorquePeakToPeak_Nm',max(q(N.Te.time_s>=lo & N.Te.time_s<hi))-min(q(N.Te.time_s>=lo & N.Te.time_s<hi)), ...
    'MeanPhaseCurrentRMS_A',mean(D.phaseRMS_A),'PeakSteadyPhaseCurrent_A',peak, ...
    'MeanGateTurnOnRate_Hz',mean(D.turnOnRates_Hz), ...
    'LoadSpeedDip_rpm',max(O.ref(after)-O.speed(after)), ...
    'LoadRecovery2pct_s',recovery,'SettledScreen',settled);
end



function plotCase(signals,c,folder)
f=figure('Visible','off','Color','w');cleanup=onCleanup(@()close(f)); %#ok<NASGU>
tiledlayout(2,1);nexttile;
plot(signals.ue_speed.time_s,signals.ue_speed.values,'b');hold on;
plot(signals.ue_ref.time_s,signals.ue_ref.values,'--k');grid on;ylabel('Speed (rpm)');
legend('Actual','Reference','Location','best');title(c.ID,'Interpreter','none');
nexttile;q=signals.ue_Te;stride=max(1,floor(numel(q.time_s)/10000));
plot(q.time_s(1:stride:end),q.values(1:stride:end,:));grid on;ylabel('Torque (Nm)');xlabel('Time (s)');
title('Retained final interval; display decimated only');
exportgraphics(f,fullfile(folder,[c.ID '_overview.png']),'Resolution',150);
end
