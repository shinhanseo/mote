import SwiftUI

struct DustBody:Shape {
 func path(in rect:CGRect)->Path {
  var p=Path()
  p.move(to:CGPoint(x:48,y:58))
  p.addCurve(to:CGPoint(x:63,y:39),control1:CGPoint(x:43,y:47),control2:CGPoint(x:52,y:37))
  p.addCurve(to:CGPoint(x:86,y:32),control1:CGPoint(x:64,y:27),control2:CGPoint(x:78,y:25))
  p.addCurve(to:CGPoint(x:114,y:32),control1:CGPoint(x:95,y:21),control2:CGPoint(x:108,y:23))
  p.addCurve(to:CGPoint(x:139,y:44),control1:CGPoint(x:127,y:26),control2:CGPoint(x:138,y:33))
  p.addCurve(to:CGPoint(x:154,y:65),control1:CGPoint(x:153,y:43),control2:CGPoint(x:160,y:54))
  p.addCurve(to:CGPoint(x:157,y:93),control1:CGPoint(x:166,y:73),control2:CGPoint(x:165,y:86))
  p.addCurve(to:CGPoint(x:145,y:119),control1:CGPoint(x:165,y:106),control2:CGPoint(x:156,y:118))
  p.addCurve(to:CGPoint(x:121,y:132),control1:CGPoint(x:144,y:132),control2:CGPoint(x:131,y:138))
  p.addCurve(to:CGPoint(x:91,y:134),control1:CGPoint(x:112,y:144),control2:CGPoint(x:98,y:143))
  p.addCurve(to:CGPoint(x:62,y:126),control1:CGPoint(x:79,y:144),control2:CGPoint(x:65,y:137))
  p.addCurve(to:CGPoint(x:42,y:107),control1:CGPoint(x:48,y:130),control2:CGPoint(x:38,y:118))
  p.addCurve(to:CGPoint(x:39,y:79),control1:CGPoint(x:29,y:100),control2:CGPoint(x:32,y:85))
  p.addCurve(to:CGPoint(x:48,y:58),control1:CGPoint(x:33,y:68),control2:CGPoint(x:39,y:60))
  p.closeSubpath()
  return p.applying(CGAffineTransform(scaleX:rect.width/200,y:rect.height/160))
 }
}

struct DustArms:Shape {
 func path(in rect:CGRect)->Path {
  var p=Path()
  p.move(to:CGPoint(x:49,y:100))
  p.addQuadCurve(to:CGPoint(x:33,y:110),control:CGPoint(x:38,y:103))
  p.addQuadCurve(to:CGPoint(x:49,y:107),control:CGPoint(x:38,y:111))
  p.move(to:CGPoint(x:150,y:101))
  p.addQuadCurve(to:CGPoint(x:166,y:110),control:CGPoint(x:161,y:103))
  p.addQuadCurve(to:CGPoint(x:150,y:107),control:CGPoint(x:160,y:111))
  return p.applying(CGAffineTransform(scaleX:rect.width/200,y:rect.height/160))
 }
}
struct DustView:View {
 var sleeping=false
 @Environment(\.colorScheme) var colorScheme
 @Environment(\.accessibilityReduceMotion) var reduceMotion
 @State private var float=false
 var body:some View {
  ZStack {
   DustArms().fill(Color(red:0.16,green:0.17,blue:0.15))
   DustBody().fill(Color(red:0.16,green:0.17,blue:0.15)).overlay {if colorScheme == .dark {DustBody().stroke(Color.white.opacity(0.22),lineWidth:0.8)}}
   GeometryReader {g in
    let sx=g.size.width/200,sy=g.size.height/160
    if sleeping {
     Path {p in p.move(to:CGPoint(x:69*sx,y:77*sy));p.addLine(to:CGPoint(x:85*sx,y:77*sy));p.move(to:CGPoint(x:109*sx,y:76*sy));p.addLine(to:CGPoint(x:125*sx,y:76*sy))}.stroke(Color(red:1,green:0.996,blue:0.96),style:StrokeStyle(lineWidth:3*sx,lineCap:.round))
     Ellipse().stroke(Color(red:1,green:0.996,blue:0.96),lineWidth:3*sx).frame(width:22*sx,height:30*sy).position(x:98*sx,y:105*sy)
    }else{
     ForEach([78.0,118.0],id:\.self){x in
      Ellipse().fill(Color(red:1,green:0.996,blue:0.96)).frame(width:18*sx,height:24*sy).position(x:x*sx,y:76*sy)
      Ellipse().fill(Color(red:0.16,green:0.17,blue:0.15)).frame(width:6.8*sx,height:10*sy).position(x:(x+2)*sx,y:78*sy)
     }
     Path {p in p.move(to:CGPoint(x:91*sx,y:102*sy));p.addQuadCurve(to:CGPoint(x:106*sx,y:102*sy),control:CGPoint(x:98*sx,y:109*sy))}.stroke(Color(red:1,green:0.996,blue:0.96),style:StrokeStyle(lineWidth:2.8*sx,lineCap:.round))
    }
   }
  }.aspectRatio(200/160,contentMode:.fit).offset(y:float && !reduceMotion ? -4:0)
   .onAppear{if !reduceMotion{withAnimation(.easeInOut(duration:2.2).repeatForever(autoreverses:true)){float=true}}}
   .accessibilityLabel(sleeping ? "쉬고 있는 먼지 요정":"먼지 요정")
 }
}
