---
name: pano-360-upload
description: 2026-11-07 38 stitched 360 JPGs uploaded and linked to all 38 destinations; awaiting phone test
metadata:
  type: project
---

Final set: 38 stitched 4096x2048 JPGs in `C:\Users\THUNDEROBOT\Pictures\Ipil 360 final\`, from user's renamed DNGs in `C:\Users\THUNDEROBOT\OneDrive\Desktop\Insta photos`. One per destination row. User said disregard the earlier phone-album set, including `Pictures\Ipil spots 360\stitched`.

Kubkub resolved by filename: `kubkub-ta-pangi` = Kubkubta, `kubkub-ta-taway` = Kubkub Ta Resto.

Stitch method: per-file calibration in DNG tail string starting `INSTA360`, lens fit 1.024, lens B rotation x 0.15 and y 1.0, level up vector (gz, gx, -gy), OpenCV COLOR_BayerGB2BGR.

DONE: uploaded to destination-images admin/panoramas, panoramic_360_url set by SQL on all 38 rows, status stayed approved. approved_snapshot not updated, so admin compare may show the pano as changed on a later owner edit. Next: user phone test.


**Why:** tourist destination page already shows the tour once the URL is set, so no app release needed. Related: [[destination-list]]

2026-11-07 HQ redo: user said 360s bad quality. All 38 re-rendered 6080x3040 (edge-aware decode, cubic remap, tone curve, edge sharpen, night cleanup) in `Pictures\Ipil 360 hq`, uploaded to admin/panoramas/hq/, rows repointed, 38 approved, key emptied. Old files in admin/panoramas/ kept for rollback. Seen in real app on phone: Anduhol good, loads under 5 s on LTE. Bayan ng Ipil night shot still grainy with blown-out building; daytime reshoot is the only fix. Preview WebView never loads since all listings have photos, so no smaller preview needed.
