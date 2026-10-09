var count = 0
for (width,height,font) in [(138.0,58.0,13.0),(328.0,82.0,16.0),(280.0,154.0,10.0)] {
 for percent in 0...100 {
  for fraction in [0.0,0.01,0.03,0.08,0.5,0.85,0.97,0.99,1.0] {
   let label = "\(percent)%" as NSString
   let f = NSFont.systemFont(ofSize:font,weight:.bold)
   let measured=label.size(withAttributes:[.font:f])
   let size=CGSize(width:ceil(measured.width)+8,height:ceil(f.ascender-f.descender)+4)
   let point=CGPoint(x:width*fraction,y:height*(1-Double(percent)/100))
   let segments:[(CGPoint,CGPoint)] = [(CGPoint(x:0,y:0),point),(point,CGPoint(x:width,y:height))]
   let r=GraphLabelPlacement.rect(point:point,label:size,plot:CGSize(width:width,height:height),segments:segments)
   let bounds=CGRect(x:0,y:0,width:width,height:height)
   precondition(bounds.contains(r),"label outside plot")
   precondition(!r.intersects(CGRect(x:point.x-5,y:point.y-5,width:10,height:10)),"label overlaps current point")
   precondition(!segments.contains{GraphLabelPlacement.intersects($0.0,$0.1,r.insetBy(dx:-3,dy:-3))},"label overlaps line")
   count += 1
  }
 }
}
print("Placement checks passed: \(count) combinations; plot bounds, point gap, actual/forecast line clearance")
