import argparse,json,statistics
from pathlib import Path
NAMES=['World overview','Overview to 20 m','Boat across chunk boundaries','Repeated panning','Distant jumps','Far-origin close view','Island/coast zoom cycling']
def summarize(path):
    data=json.loads(Path(path).read_text());rows=data['rows'];lines=['# Recorded benchmark','',f"Engine: {data['engine']['string']}; OS: {data['os']}; GPU: {data['adapter']}; viewport: {data['viewport']}; headless: {data['headless']}",'','Frame times use consecutive monotonic wall-clock timestamps. First two seconds of each phase are excluded from routine statistics; all-phase maxima and >50 ms counts remain reported. Vsync is enabled. This is a short scenario run, not a sustained acceptance certification.','','| Scenario | Routine FPS | Routine p95 ms | All max ms | All >50 ms | Estimated geography MiB |','|---|---:|---:|---:|---:|---:|']
    for phase,name in enumerate(NAMES):
        rr=[r for r in rows if r['phase']==phase];elapsed=0;steady=[]
        for r in rr:
            elapsed+=r['ms']
            if elapsed>2000:steady.append(r['ms'])
        if not steady:steady=[r['ms'] for r in rr]
        ordered=sorted(steady);p95=ordered[min(len(ordered)-1,int(.95*len(ordered)))];fps=1000/statistics.mean(steady)
        lines.append(f"| {name} | {fps:.2f} | {p95:.2f} | {max(r['ms'] for r in rr):.2f} | {sum(r['ms']>50 for r in rr)} | {max(r['bytes_est'] for r in rr)/1048576:.2f} |")
    lines.extend(['',f"Whole-run mean FPS: {1000/statistics.mean(r['ms'] for r in rows):.2f}.",f"Peak engine static memory: {max(r.get('engine_static_bytes',0) for r in rows)/1048576:.2f} MiB.",f"Peak reported video memory: {max(r.get('video_bytes',0) for r in rows)/1048576:.2f} MiB (backend-dependent; zero means unavailable).",f"Peak draw calls: {max(r.get('draw_calls',0) for r in rows):.0f}."])
    travel=[r for r in rows if r['phase']==2]
    if travel and 'boat_east' in travel[0]:
        keys={(int(r['boat_east']//1024),int(r['boat_south']//1024)) for r in travel}
        lines.append(f"Boat traversal visited {len(keys)} geographic chunks; blocked frames: {sum(r['boat_blocked'] for r in travel)}.")
    return '\n'.join(lines)+'\n'
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('input');p.add_argument('--output');a=p.parse_args();result=summarize(a.input)
    if a.output:Path(a.output).write_text(result,encoding='utf8')
    else:print(result)
