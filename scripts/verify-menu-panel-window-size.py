from pathlib import Path
import subprocess,tempfile
p=Path(__file__).resolve().parent.parent/'Sources/CodexUsageMonitorApp/UsagePanel.swift'
s=p.read_text();helper=s[s.index('private struct PanelWindowSize: NSViewRepresentable {'):s.index('private struct ContentHeightPreferenceKey: PreferenceKey {')]
program='''import AppKit
import SwiftUI
'''+helper+'''
@MainActor @main struct Verify {
 static func main() throws {
  _ = NSApplication.shared
  let window = NSWindow(contentRect:NSRect(x:200,y:200,width:360,height:680),styleMask:[.borderless],backing:.buffered,defer:false)
  window.alphaValue = 0
  let sizing = PanelSizingView()
  sizing.requestedHeight=520
  window.contentView?.addSubview(sizing)
  for _ in 0..<10 { RunLoop.main.run(until:Date().addingTimeInterval(0.02)) }
  precondition(abs(window.contentLayoutRect.height-520)<1,"initial hidden window mismatch")
  let top=window.frame.maxY
  window.orderFront(nil)
  for _ in 0..<10 { RunLoop.main.run(until:Date().addingTimeInterval(0.02)) }
  precondition(window.isVisible,"window did not open")
  sizing.requestedHeight=310
  for _ in 0..<10 { RunLoop.main.run(until:Date().addingTimeInterval(0.02)) }
  precondition(abs(window.contentLayoutRect.height-310)<1,"window did not shrink")
  precondition(abs(window.frame.maxY-top)<1,"top edge moved")
  window.orderOut(nil)
  sizing.requestedHeight=600
  for _ in 0..<10 { RunLoop.main.run(until:Date().addingTimeInterval(0.02)) }
  precondition(!window.isVisible,"window unexpectedly visible")
  precondition(abs(window.contentLayoutRect.height-600)<1,"hidden window did not grow")
  precondition(abs(window.frame.maxY-top)<1,"top edge moved while hidden")
  window.orderFront(nil)
  for _ in 0..<10 { RunLoop.main.run(until:Date().addingTimeInterval(0.02)) }
  precondition(abs(window.contentLayoutRect.height-600)<1,"reopened window mismatch")
  precondition(abs(window.frame.maxY-top)<1,"top edge moved after reopen")
  window.close()
  print("Panel window fit: hidden 680→520→310→hidden 600→reopen, fixed top edge; PASS")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='panel-size-test-') as d:
 src=Path(d)/'PanelSize.swift';src.write_text(program)
 subprocess.run(['swiftc','-parse-as-library',str(src),'-o',str(Path(d)/'check')],check=True)
 subprocess.run([str(Path(d)/'check')],check=True)
