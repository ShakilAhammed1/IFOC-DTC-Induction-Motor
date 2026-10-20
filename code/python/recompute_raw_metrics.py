"""Stage12 raw-data audit. Usage: python recompute_raw_metrics.py INPUT_FOLDER OUTPUT_FOLDER
Dependencies: numpy scipy h5py matplotlib. No MATLAB simulations are performed.
"""
import sys,json,csv,hashlib,html
from pathlib import Path
import numpy as np
import h5py
from scipy.signal import resample_poly
from scipy.optimize import minimize_scalar
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

root=Path(sys.argv[1]); out=Path(sys.argv[2]);out.mkdir(parents=True,exist_ok=True)
cases=[('IFOC nominal', 'IFOC_R1000_E1000_L100_N1600_B1000'), ('IFOC Rr+50% mismatch', 'IFOC_R1500_E1000_L100_N1600_B1000'), ('IFOC Rr+50% corrected', 'IFOC_R1500_E1500_L100_N1600_B1000'), ('DTC nominal', 'DTC_R1000_E1000_L100_N1600_B0010'), ('DTC half load', 'DTC_R1000_E1000_L050_N1600_B0010'), ('DTC 900 rpm', 'DTC_R1000_E1000_L100_N900_B0010'), ('DTC Rr+50%', 'DTC_R1500_E1000_L100_N1600_B0010'), ('IFOC half load', 'IFOC_R1000_E1000_L050_N1600_B1000'), ('IFOC 900 rpm', 'IFOC_R1000_E1000_L100_N900_B1000'), ('DTC nominal fine', 'DTC_R1000_E1000_L100_N1600_B0010_h3125'), ('IFOC Rr+50% mismatch fine', 'IFOC_R1500_E1000_L100_N1600_B1000_h3125'), ('IFOC Rr+50% corrected fine', 'IFOC_R1500_E1500_L100_N1600_B1000_h3125'), ('DTC 900 rpm fine', 'DTC_R1000_E1000_L100_N900_B0010_h3125')]

def fit(t,y,fr,H=50):
 A=np.column_stack([np.ones(len(t))]+[v for n in range(1,H+1) for v in (np.cos(2*np.pi*n*fr*t),np.sin(2*np.pi*n*fr*t))])
 c=np.linalg.lstsq(A,y,rcond=None)[0]
 return c,np.hypot(c[1::2],c[2::2]),A
def txt(d): return ''.join(chr(int(x)) for x in np.array(d).ravel())
def scalar(g,k): return float(np.asarray(g[k]).ravel()[0])
def writecsv(name,rows):
 with (out/name).open('w',newline='') as f:
  w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
t=np.arange(20000)/40000
y=np.cos(2*np.pi*50*t)+.03*np.cos(2*np.pi*250*t)+.02*np.sin(2*np.pi*350*t)
_,amp,_=fit(t,y,50)
synthetic=float(100*np.linalg.norm(amp[1:])/amp[0]);assert abs(synthetic-np.sqrt(13))<1e-8
rows=[];audit={};manifest={};traces={};specs={}
for label,case in cases:
 path=root/(case+'_data.mat')
 manifest[path.name]=hashlib.sha256(path.read_bytes()).hexdigest()
 with h5py.File(path,'r') as f:
  assert bool(f['completed'][()].ravel()[0])
  assert txt(f['execution/StopEvent'])=='ReachedStopTime'
  settings={k:(txt(v) if v.attrs.get('MATLAB_class')==b'char' else float(np.array(v).ravel()[0])) for k,v in f['settings'].items()}
  lo=settings['WindowStart_s'];hi=settings['Stop_s'];mid=(lo+hi)/2
  def get(name):
   g=f['signals/'+name];t=np.array(g['time_s']).ravel();v=np.array(g['values']).T
   assert len(t)==len(v) and np.all(np.isfinite(t)) and np.all(np.isfinite(v)) and np.all(np.diff(t)>0), name
   assert t[0]<=lo and t[-1]>=hi-1e-4,name
   return t,v
  ts,sp=get('ue_speed');tr,rf=get('ue_ref');sp=sp[:,0];rf=np.interp(ts,tr,rf[:,0]);err=sp-rf
  k=(ts>=lo)&(ts<hi);ref=float(np.median(rf[k]));after=ts>=1.6
  outside=np.flatnonzero(after&(np.abs(err)>.02*ref))
  recovery=0. if not len(outside) else (float('nan') if outside[-1]==len(ts)-1 else float(ts[outside[-1]+1]-1.6))
  tq,te=get('ue_Te');te=te[:,0];q=te[(tq>=lo)&(tq<hi)]
  ti,cur=get('ue_Iabc');ii=cur[(ti>=lo)&(ti<hi)]
  tg,g=get('ue_gates');assert g.shape[1]==6 and np.all(np.isin(g,[0,1]))
  events=(tg[1:]>=lo)&(tg[1:]<hi);rates=np.sum(np.diff(g,axis=0)[events]>0,axis=0)/(hi-lo)
  speeddrift=float(sp[(ts>=mid)&(ts<hi)].mean()-sp[(ts>=lo)&(ts<mid)].mean())
  torquedrift=float(te[(tq>=mid)&(tq<hi)].mean()-te[(tq>=lo)&(tq<mid)].mean())
  rms1=np.sqrt(np.mean(cur[(ti>=lo)&(ti<mid)]**2));rms2=np.sqrt(np.mean(cur[(ti>=mid)&(ti<hi)]**2))
  idrift=float(100*abs(rms2-rms1)/max(rms1,np.finfo(float).eps))
  tbase=scalar(f['parameters'],'Tbase')
  settled=abs(torquedrift)/tbase*100<1 and abs(speeddrift)<1 and idrift<1 and abs(err[k]).mean()<.01*ref
  if settings['Controller']=='IFOC':
   tv,vv=get('s2_vdq_limited');tl,lim=get('s2_voltage_limit');util=np.linalg.norm(vv,axis=1)/np.maximum(np.abs(np.interp(tv,tl,lim[:,0])),np.finfo(float).eps)
   tx,iq=get('s2_iq_ref');kw=(tx>=lo)&(tx<hi);vw=(tv>=lo)&(tv<hi)
   iqfrac=float(np.mean(abs(iq[kw,0])>=1.98));vfrac=float(np.mean(util[vw]>=.99))
  else:
   tx=tv=ts; iq=np.full((len(ts),1),np.nan);util=np.full(len(ts),np.nan)
   iqfrac=vfrac=float('nan')
  base=dict(Case=case,Label=label,SettledScreen=int(settled),MeanSpeed_rpm=float(sp[k].mean()),SpeedMAE_rpm=float(abs(err[k]).mean()),MeanTorque_Nm=float(q.mean()),TorqueStd_Nm=float(q.std()),CurrentRMS_A=float(np.sqrt(np.mean(ii**2,axis=0)).mean()),GateRate_Hz=float(rates.mean()),LoadSpeedDip_rpm=float(np.max(rf[after]-sp[after])),Recovery2pct_s=recovery,IqLimitFraction=iqfrac,Voltage99Fraction=vfrac)
  mappings={'SpeedMAE_rpm':'SpeedMAE_rpm','MeanTorque_Nm':'MeanTorque_Nm','TorqueStd_Nm':'TorqueRMS_Nm','CurrentRMS_A':'MeanPhaseCurrentRMS_A','GateRate_Hz':'MeanGateTurnOnRate_Hz','LoadSpeedDip_rpm':'LoadSpeedDip_rpm','Recovery2pct_s':'LoadRecovery2pct_s','IqLimitFraction':'IqLimitFraction','Voltage99Fraction':'Voltage99Fraction','SettledScreen':'SettledScreen'}
  diffs={}
  for key,storedkey in mappings.items():
   stored=scalar(f['S'],storedkey);actual=base[key]
   assert np.isclose(actual,stored,rtol=1e-8,atol=1e-8,equal_nan=True),(case,key,actual,stored)
   diffs[key]=None if np.isnan(actual) else float(actual-stored)
  dt=np.median(np.diff(ti));assert np.max(abs(np.diff(ti)-dt))<1e-14+dt*1e-8
  dec=round(1/dt/40000);fs=1/(dt*dec);assert abs(fs-40000)<.01
  v=resample_poly(cur,1,dec,axis=0,window=('kaiser',12));tt=ti[0]+np.arange(len(v))/fs
  keep=(tt>=lo+.01)&(tt<hi-.01);u=tt[keep]-mid;y=v[keep]
  def cost(fr):
   c,_,A=fit(u[::5],y[::5],fr,1);return np.sum((y[::5]-A@c)**2)
  grid=np.arange(20,70,.25);ix=int(np.argmin([cost(fr) for fr in grid]));assert 0<ix<len(grid)-1
  fr=float(minimize_scalar(cost,bounds=(grid[ix-1],grid[ix+1]),method='bounded',options={'xatol':1e-9}).x)
  windows=[]
  for center,cycles in [(mid,20),(mid-.1,10),(mid+.1,10)]:
   left,right=center-cycles/(2*fr),center+cycles/(2*fr);assert left>=lo and right<=hi
   kk=(tt>=left)&(tt<right);u=tt[kk]-center;y=v[kk]
   c,amp,A=fit(u,y,fr);thd=100*np.linalg.norm(amp[1:],axis=0)/amp[0]
   cf,af,Af=fit(u,y,fr,1);res=y-Af@cf
   residual=100*np.sqrt(np.mean(res**2,axis=0))/(af[0]/np.sqrt(2))
   windows.append(dict(cycles=cycles,start_s=left,end_s=right,THD50_phases_pct=thd.tolist(),Residual40k_phases_pct=residual.tolist()))
   if cycles==20:
    win=np.hanning(len(y));freqs=np.fft.rfftfreq(len(y),1/fs);amps=2*abs(np.fft.rfft((y[:,0]-cf[0,0])*win))/sum(win)/af[0,0]*100
    specs[label]=(freqs,amps)
  thds=[float(np.mean(w['THD50_phases_pct'])) for w in windows];rs=[float(np.mean(w['Residual40k_phases_pct'])) for w in windows]
  base.update(Fundamental_Hz=fr,THD50_pct=thds[0],THD50_window_min_pct=min(thds),THD50_window_max_pct=max(thds),Residual40k_pct=rs[0],Interpretation='tracking case' if settled else 'failed tracking; spectral values diagnostic only')
  rows.append(base)
  audit[case]=dict(settings=settings,stop_event=txt(f['execution/StopEvent']),final_speed_time_s=float(ts[-1]),retained_current_range_s=[float(ti[0]),float(ti[-1])],retained_current_samples=len(ti),original_current_step_s=float(dt),resampled_Hz=float(fs),summary_differences=diffs,phase_gate_rates_Hz=rates.tolist(),speed_drift_rpm=speeddrift,torque_drift_Nm=torquedrift,current_RMS_drift_pct=idrift,spectral_windows=windows)
  traces[label]=(ts[::10],sp[::10],rf[::10])
  print(json.dumps(base),flush=True)
writecsv('all_raw_metrics.csv',rows)
(out/'audit.json').write_text(json.dumps(audit,indent=2))
(out/'source_sha256.json').write_text(json.dumps(manifest,indent=2))
(out/'spectral_estimator_check.json').write_text(json.dumps({'synthetic_expected_pct':float(np.sqrt(13)),'synthetic_calculated_pct':synthetic},indent=2))
