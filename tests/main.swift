import Foundation
func check(_ condition: Bool, _ message: String) {
    if !condition { fatalError(message) }
}
let qcom = """
--video-codec=h264 --video-encoder=c2.android.avc.encoder (sw)
--video-codec=h264 --video-encoder=OMX.qcom.video.encoder.avc (hw) [vendor] (alias for c2.qti.avc.encoder)
--video-codec=h264 --video-encoder=c2.qti.avc.encoder (hw) [vendor]
"""
check(ScreenReceiver.selectHardwareEncoder(qcom) == "c2.qti.avc.encoder", "Qualcomm native encoder")
check(ScreenReceiver.selectHardwareEncoder("--video-codec=h264 --video-encoder=c2.mtk.avc.encoder (hw) [vendor]") == "c2.mtk.avc.encoder", "MediaTek hardware")
check(ScreenReceiver.selectHardwareEncoder("--video-codec=h264 --video-encoder=OMX.Exynos.AVC.Encoder (hw) [vendor]") == "OMX.Exynos.AVC.Encoder", "Exynos hardware")
check(ScreenReceiver.selectHardwareEncoder("--video-codec=h264 --video-encoder=c2.android.avc.encoder (sw)") == nil, "Reject software-only")
check(ScreenReceiver.selectHardwareEncoder("--video-codec=h265 --video-encoder=c2.qti.hevc.encoder (hw) [vendor]") == nil, "Reject incompatible codec")
check(ScreenReceiver.selectHardwareEncoder("") == nil, "Reject empty list")
check(ScreenReceiver.splitNALs([0,0,0,1,0x67,0x42,0,0,1,0x68,0x7f]) == [[0x67,0x42],[0x68,0x7f]], "Parse mixed Annex-B start codes")
print("7 compatibility/parser checks passed")
