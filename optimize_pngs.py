import os
from PIL import Image

DIR = r"D:\Godot\assets\creatures"
total_before = 0
total_after = 0
shrunk = 0
skipped = 0

for name in sorted(os.listdir(DIR)):
    if not name.lower().endswith(".png"):
        continue
    path = os.path.join(DIR, name)
    before = os.path.getsize(path)
    total_before += before

    tmp = path + ".tmp.png"
    try:
        with Image.open(path) as img:
            img.save(tmp, format="PNG", optimize=True, compress_level=9)
    except Exception as e:
        if os.path.exists(tmp):
            os.remove(tmp)
        print(f"ERR  {name}: {e}")
        total_after += before
        continue

    after = os.path.getsize(tmp)
    if after < before:
        os.replace(tmp, path)
        total_after += after
        shrunk += 1
        print(f"OK   {name:30} {before//1024:>5}KB -> {after//1024:>5}KB  (saved {(before-after)//1024}KB)")
    else:
        os.remove(tmp)
        total_after += before
        skipped += 1

print(f"\n--- Summary ---")
print(f"Files shrunk:   {shrunk}")
print(f"Files skipped:  {skipped}")
print(f"Total before:   {total_before/1024/1024:.1f} MB")
print(f"Total after:    {total_after/1024/1024:.1f} MB")
print(f"Saved:          {(total_before-total_after)/1024/1024:.1f} MB")
