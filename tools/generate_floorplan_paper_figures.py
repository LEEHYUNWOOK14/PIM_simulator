#!/usr/bin/env python3
"""Generate deterministic paper figures from candidate evidence artifacts."""
from __future__ import annotations

import csv
import json
from pathlib import Path

import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Circle, Rectangle
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output/floorplan_optimization/visualization/paper_figures"
COLORS = {"data":"#1f77b4","command_address":"#ff7f0e","clock":"#e377c2","power":"#d62728","ground":"#444444","spare":"#bcbd22","unknown":"#7f7f7f"}


def load_csv(path: str) -> list[dict]:
    with (ROOT / path).open(newline="",encoding="utf-8") as stream: return list(csv.DictReader(stream))


def manifest(strategy: str) -> dict:
    return json.loads((ROOT / f"output/floorplan_optimization/exploration/candidates/{strategy}.json").read_text(encoding="utf-8"))


def draw_floorplan(ax, data: dict, title: str, labels: bool = False, thermal=None) -> None:
    ax.set_xlim(0,8); ax.set_ylim(0,12); ax.set_aspect("equal"); ax.set_xlabel("x (mm)"); ax.set_ylabel("y (mm)"); ax.set_title(title,fontsize=10)
    if thermal is not None: ax.imshow(thermal,origin="lower",extent=[0,8,0,12],cmap="inferno",alpha=.58,aspect="auto")
    for region in data["reserved_regions"]:
        ax.add_patch(Rectangle((region["x_um"]/1000,region["y_um"]/1000),region["width_um"]/1000,region["height_um"]/1000,facecolor="none",edgecolor="#9467bd",hatch="//",lw=.8,alpha=.8))
    for corridor in data["routing_corridors"]:
        ax.add_patch(Rectangle((corridor["x_um"]/1000,corridor["y_um"]/1000),corridor["width_um"]/1000,corridor["height_um"]/1000,facecolor="#00bcd4",edgecolor="none",alpha=.12))
    palette=plt.cm.Set2(np.linspace(0,1,len(data["blocks"])))
    for color,block in zip(palette,data["blocks"]):
        x,y,w,h=[block[k]/1000 for k in ("x_um","y_um","width_um","height_um")]; ax.add_patch(Rectangle((x,y),w,h,facecolor=color,edgecolor="white",lw=1.2,alpha=.75))
        if labels: ax.text(x+w/2,y+h/2,block["module"].replace("logic_die_","").replace("bank_local_","bank_").replace("shared_fp16_","fp16_"),ha="center",va="center",fontsize=5,rotation=90 if h>w*2 else 0)
    for bundle in data["tsv_bundles"]:
        x=(bundle["x_um"]+(bundle["columns"]-1)*bundle["pitch_um"]/2)/1000; y=(bundle["y_um"]+(bundle["rows"]-1)*bundle["pitch_um"]/2)/1000
        ax.scatter(x,y,s=8,c=COLORS[bundle["signal_class"]],marker="o",edgecolors="none")
    ax.grid(alpha=.15)


def save(fig, name: str) -> None:
    fig.text(.01,.006,"Modeled/estimated research visualization; provisional floorplan; not manufacturing or thermal signoff.",fontsize=7,color="#555")
    fig.tight_layout(rect=[0,.025,1,1]); fig.savefig(OUT/f"{name}.png",dpi=300); fig.savefig(OUT/f"{name}.svg"); plt.close(fig)


def main() -> int:
    OUT.mkdir(parents=True,exist_ok=True)
    data=manifest("thermal_first")
    fig,ax=plt.subplots(figsize=(6.4,8.4)); draw_floorplan(ax,data,"Logic die blocks, reserved regions, corridors, and TSV bundles",True)
    handles=[plt.Line2D([],[],marker='o',ls='',color=color,label=key) for key,color in COLORS.items() if key!="unknown"]
    ax.legend(handles=handles,ncol=2,fontsize=7,loc="upper right"); save(fig,"figure_02_logic_die_tsv_coordinates")

    strategies=["manual_baseline","wirelength_first","thermal_first","balanced"]
    fig,axes=plt.subplots(1,4,figsize=(14,5.8),sharex=True,sharey=True)
    for ax,strategy in zip(axes,strategies): draw_floorplan(ax,manifest(strategy),strategy.replace("_"," "))
    save(fig,"figure_03_candidate_placement_comparison")

    physical=load_csv("output/floorplan_optimization/openroad_proxy/openroad_proxy_metrics.csv"); order=strategies
    physical={row["strategy"]:row for row in physical}; fig,axes=plt.subplots(2,1,figsize=(9,7),sharex=True)
    bottom=np.zeros(len(order)); layer_colors={"met2":"#4c78a8","met3":"#f58518","met4":"#54a24b","met5":"#e45756"}
    for layer,color in layer_colors.items():
        values=np.array([float(physical[s][f"{layer}_wirelength_um"])/1000 for s in order]); axes[0].bar(order,values,bottom=bottom,label=layer,color=color); bottom+=values
    axes[0].set_ylabel("Global-route wirelength (mm)"); axes[0].legend(ncol=4); axes[0].set_title("Manifest macro proxy — OpenROAD 26Q3 global route")
    overflow=[float(physical[s]["global_route_overflow_sum"]) for s in order]; bins=[float(physical[s]["congestion_violation_bins"]) for s in order]
    x=np.arange(len(order)); axes[1].bar(x-.18,overflow,.36,label="overflow sum",color="#d62728"); axes[1].bar(x+.18,bins,.36,label="violation bins",color="#9467bd"); axes[1].set_xticks(x,[s.replace("_","\n") for s in order]); axes[1].set_ylabel("Reported congestion count"); axes[1].legend(); save(fig,"figure_04_openroad_routing_congestion")

    with np.load(ROOT/"output/floorplan_optimization/thermal/thermal_first/temperature_field.npz") as fields:
        temperature=fields["temperature_K"]; power=fields["power_W_cell"]
    logic_temp=temperature[2]; logic_power=power[2]; fig,axes=plt.subplots(1,2,figsize=(11,5.4))
    im=axes[0].imshow(logic_power,origin="lower",extent=[0,8,0,12],cmap="magma",aspect="auto"); fig.colorbar(im,ax=axes[0],label="Power (W/grid cell)"); axes[0].set_title("thermal_first — estimated 4 W raster")
    im=axes[1].imshow(logic_temp-273.15,origin="lower",extent=[0,8,0,12],cmap="inferno",aspect="auto"); fig.colorbar(im,ax=axes[1],label="Temperature (°C)"); axes[1].set_title("Reference finite-volume logic layer")
    for ax in axes: ax.set(xlabel="x (mm)",ylabel="y (mm)")
    save(fig,"figure_05_power_temperature_heatmaps")

    comparison=load_csv("output/floorplan_optimization/candidate_comparison.csv"); unique={row["candidate_id"]:row for row in comparison}.values(); fig,axes=plt.subplots(1,2,figsize=(11,4.8))
    markers={"manual_baseline":"o","wirelength_first":"s","thermal_first":"^","balanced":"D"}
    for row in unique:
        strategy=row["strategy"]; temp=float(row["reference_peak_temperature_C"]); cost=float(row["candidate_structural_cost_proxy"]); wire=float(row["openroad_global_route_wirelength_um"])/1000; overflow=float(row["global_route_overflow_sum"])
        axes[0].scatter(cost,temp,s=90,marker=markers.get(strategy,"o"),label=strategy,c=overflow,cmap="viridis",vmin=0,vmax=358,edgecolor="black"); axes[1].scatter(wire,temp,s=90,marker=markers.get(strategy,"o"),label=strategy,c=overflow,cmap="viridis",vmin=0,vmax=358,edgecolor="black")
        axes[0].annotate(strategy.replace("_"," "),(cost,temp),xytext=(4,4),textcoords="offset points",fontsize=7); axes[1].annotate(strategy.replace("_"," "),(wire,temp),xytext=(4,4),textcoords="offset points",fontsize=7)
    axes[0].set(xlabel="Normalized structural cost proxy",ylabel="Reference peak temperature (°C)",title="Cost–temperature trade-off"); axes[1].set(xlabel="OpenROAD global-route wirelength (mm)",ylabel="Reference peak temperature (°C)",title="Wirelength–temperature trade-off")
    for ax in axes: ax.grid(alpha=.2)
    save(fig,"figure_06_cost_wire_temperature_pareto")

    figure_manifest={
        "status":"PASS","fixed_axes_mm":[0,8,0,12],"dpi":300,"figures":{
            "figure_01_hbm_stack_3d.png":{"generator":"ParaView 6.1.1 / RTX 4060","claim":"modeled stack, TSV centerlines, block overlay and temperature; z scale 20x exaggerated"},
            "figure_02_logic_die_tsv_coordinates.png":{"claim":"canonical manifest coordinates and bundle signal classes"},
            "figure_03_candidate_placement_comparison.png":{"claim":"same-scale provisional candidate geometry"},
            "figure_04_openroad_routing_congestion.png":{"claim":"global-routed conceptual macro proxy only"},
            "figure_05_power_temperature_heatmaps.png":{"claim":"estimated 4 W reference finite-volume field; not calibrated"},
            "figure_06_cost_wire_temperature_pareto.png":{"claim":"normalized cost proxy and modeled physical/thermal trade-off"}},
        "raw_klayout_images":"output/floorplan_optimization/visualization/<strategy>/klayout_fixed_camera.png","signoff":False}
    (OUT/"figure_manifest.json").write_text(json.dumps(figure_manifest,indent=2),encoding="utf-8")
    print(f"FLOORPLAN_PAPER_FIGURES PASS output={OUT}"); return 0


if __name__=="__main__": raise SystemExit(main())
