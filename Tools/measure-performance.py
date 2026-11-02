#!/usr/bin/env python3
"""Read-only macOS process CPU/footprint sampling; no conversations are collected."""
import argparse,json,statistics,subprocess
p=argparse.ArgumentParser();p.add_argument('--pid',type=int,required=True);p.add_argument('--samples',type=int,default=16);p.add_argument('--interval',type=int,default=2);a=p.parse_args()
if a.samples<2 or a.interval<1:p.error('Use at least 2 samples and a positive interval')
result=subprocess.run(['top','-l',str(a.samples),'-s',str(a.interval),'-pid',str(a.pid),'-stats','pid,cpu,mem'],text=True,capture_output=True,check=True)
rows=[]
for line in result.stdout.splitlines():
 fields=line.split()
 if len(fields)==3 and fields[0]==str(a.pid):
  try:rows.append({'cpu_percent':float(fields[1]),'footprint':fields[2]})
  except ValueError:pass
if len(rows)<2:raise SystemExit('Process exited or samples unavailable')
values=[row['cpu_percent'] for row in rows[1:]] # first top sample is not an interval
print(json.dumps({'pid':a.pid,'interval_seconds':a.interval,'sample_count':len(values),'cpu_mean':round(statistics.mean(values),2),'cpu_median':statistics.median(values),'cpu_max':max(values),'samples':rows[1:]},indent=2))
