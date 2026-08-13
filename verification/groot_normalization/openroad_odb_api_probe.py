import openroad
import odb

print("DESIGN", [name for name in dir(openroad.Design) if "db" in name.lower() or "block" in name.lower()])

design = openroad.Design(openroad.Tech())
block_cls = openroad.ord.get_db_block if False else None

for cls_name in ("dbBlock", "dbRegion", "dbGroup", "dbInst", "dbBox"):
    cls = getattr(odb, cls_name)
    names = [name for name in dir(cls) if any(key in name.lower() for key in ("region", "group", "inst", "box", "bound", "type", "create", "destroy"))]
    print(cls_name, names)
    for name in names:
        if name in ("create", "addInst", "setRegionType", "setType"):
            print("DOC", cls_name, name, getattr(cls, name).__doc__)
