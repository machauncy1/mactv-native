import Foundation

struct BilibiliNextEpisode:Codable,Equatable {
    let url:String
    let title:String
    var validURL:URL? {
        guard let value=URL(string:url),value.scheme=="https",["www.bilibili.com","bilibili.com"].contains(value.host ?? ""),value.user==nil,value.password==nil,value.port==nil,
              value.path.range(of:"^/(bangumi/play/ep[0-9]+|video/BV[A-Za-z0-9]+)/?$",options:.regularExpression) != nil else{return nil}
        return value
    }
}

// Monotonic deadlines keep the countdown accurate if rendering or polling is delayed.
struct EpisodeCountdown {
    private(set) var mediaKey=""
    private(set) var handled=false
    private(set) var target:BilibiliNextEpisode?
    private(set) var remaining=0
    private var deadline:TimeInterval?
    mutating func observe(key:String,ended:Bool,rewound:Bool,eligible:Bool,next:BilibiliNextEpisode?,now:TimeInterval){
        if key != mediaKey {self=EpisodeCountdown();mediaKey=key}
        if !ended {
            cancel()
            if rewound {handled=false}
            return
        }
        guard eligible else{cancel();handled=true;return}
        guard !handled,let next,next.validURL != nil else{return}
        handled=true;target=next;deadline=now+10;remaining=10
    }
    mutating func tick(now:TimeInterval)->BilibiliNextEpisode? {
        guard let deadline,let target else{return nil}
        remaining=max(0,Int(ceil(deadline-now)))
        guard remaining==0 else{return nil}
        cancel();return target
    }
    mutating func cancel(){target=nil;deadline=nil;remaining=0}
    mutating func reset(){self=EpisodeCountdown()}
}
