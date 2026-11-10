const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const root={textContent:'',setAttribute(){},removeAttribute(){}};const videoAttributes={};
const video={getBoundingClientRect(){return {width:this.clientWidth,height:this.clientHeight}},tagName:'VIDEO',clientWidth:1920,clientHeight:1080,currentTime:20,duration:100,paused:false,ended:false,seeking:false,readyState:4,closest:()=>root,parentElement:root,getAttribute:key=>videoAttributes[key],setAttribute:(key,value)=>videoAttributes[key]=value,removeAttribute:key=>delete videoAttributes[key],pause(){this.paused=true},async play(){this.paused=false}};
let destination='',accountNodes={},modern=[],parts=[],pod=[];const notices=[{textContent:'即将播放第九集',setAttribute(key){this.hidden=key==='data-mactv-native-notice'}},{textContent:'本片是大会员专享内容',setAttribute(){this.hidden=true}}];
const events={};
const location={hostname:'www.bilibili.com',pathname:'/video/BVTwo/',origin:'https://www.bilibili.com',search:'',get href(){return this.origin+this.pathname+this.search},assign:url=>{destination=url}};
function node({href='',bvid='',number='',title='视频',cls=''}) {
 return {isConnected:true,href,className:cls,textContent:title,getBoundingClientRect:()=>({width:80,height:40}),getAttribute:name=>name==='data-key'?bvid:name==='title'?number:null,matches:selector=>selector==='a[href]'&&!!href,querySelector:selector=>selector==='a[href]'?(href?{href}:null):selector.includes('numberTitle')?(number?{textContent:number}:null):selector==='.title-txt,.title'?{textContent:title}:selector==='.index,.page-num,.episode-index'?(number?{textContent:number}:null):null};
}
const document={
 documentElement:{setAttribute(){}},
 querySelectorAll:selector=>selector.startsWith('.bpx-player-container [class*=')?notices:selector==='video'?[video]:selector.startsWith('a[class*=')?modern:selector==='#multi_page .list-box li'?parts:selector==='.video-pod__item'?pod:[],
 querySelector:selector=>accountNodes[selector]||null,getElementById:()=>true,
 addEventListener:(name,handler)=>{(events[name]??=[]).push(handler)}
};
const context={window:{},location,document,URL,URLSearchParams,getComputedStyle:()=>({visibility:'hidden'})};
vm.runInNewContext(fs.readFileSync('Resources/Bilibili/episode-guard.js','utf8'),context);
vm.runInNewContext(fs.readFileSync('Resources/Bilibili/adapter.js','utf8'),context);
(async()=>{
 const api=context.window.MacTVBilibili;
 video.readyState=1;assert.equal(api.playerReady(),false,'metadata alone must not reveal blank player');
 video.readyState=2;assert.equal(api.playerReady(),true,'decoded frame with cinema layout may be revealed');
 video.clientWidth=0;assert.equal(api.playerReady(),false,'zero size player is not ready');video.clientWidth=1920;video.readyState=4;
 assert.equal(api.snapshot().loggedIn,null);assert.equal(notices[0].hidden,true,'suppress duplicate official next/resume notices');assert.equal(notices[1].hidden,undefined,'leave membership notices intact');
 accountNodes['.header-avatar-wrap img,.header-entry-mini img']={getBoundingClientRect:()=>({width:36,height:36})};
 assert.equal(api.snapshot().loggedIn,true,'restore hidden cinema header account');
 accountNodes['.header-login-entry']={textContent:'登录',getBoundingClientRect:()=>({width:50,height:30})};
 assert.equal(api.snapshot().loggedIn,false);accountNodes={};
 await api.media('seek',200);assert.equal(video.currentTime,100);
 await api.media('seek',-20);assert.equal(video.currentTime,0);
 await api.media('seek',NaN);assert.equal(video.currentTime,0);
 await api.media('right');assert.equal(video.currentTime,10);
 pod=['BVOne','BVTwo','BVThree'].map((bvid,i)=>node({bvid,title:'合集 '+(i+1)}));
 let state=api.snapshot();assert.equal(state.episodes[1].current,true);assert.equal(state.nextEpisode.url,'https://www.bilibili.com/video/BVThree/');
 assert.equal(api.activate(state.episodes[0].id),true);assert.equal(destination,'https://www.bilibili.com/video/BVOne/','data-key collection links navigate directly');
 assert.equal(api.advanceNext(state.nextEpisode.url),false,'cannot advance before actual end');
 let stopped=0;video.ended=true;
 events.ended[0]({type:'ended',target:video,stopImmediatePropagation(){stopped++}});
 assert.equal(stopped,1,'capture prevents site racing native countdown');assert.equal(api.snapshot().ended,true);
 assert.equal(api.advanceNext('https://other.test/video/BVThree/'),false);
 assert.equal(api.advanceNext('https://www.bilibili.com/video/BVThree/'),true);assert.equal(destination,'https://www.bilibili.com/video/BVThree/');
 root.textContent='本片是大会员专享内容';assert.equal(api.snapshot().trial,true);assert.equal(api.advanceNext('https://www.bilibili.com/video/BVThree/'),false,'trial never advances');root.textContent='';
 video.currentTime=20;video.ended=false;events.seeking[0]({target:video});assert.equal(api.snapshot().ended,false,'replay rearms actual end event');
 video.currentTime=99.98;video.paused=false;events.timeupdate[0]({type:'timeupdate',target:video,stopImmediatePropagation(){stopped++}});assert.equal(api.snapshot().ended,true,'MSE final timeupdate can end playback without ended event');assert.equal(video.paused,true);video.currentTime=20;events.seeking[0]({target:video});
 location.pathname='/video/BVThree/';assert.equal(api.nextEpisode(),null,'last collection item');pod=[];assert.equal(api.nextEpisode(),null,'single video has no fabricated next');
 location.pathname='/video/BVParts/';location.search='?p=1';parts=[1,2].map(n=>node({href:'https://www.bilibili.com/video/BVParts/?p='+n,number:String(n),title:'分P '+n}));
 assert.equal(api.nextEpisode().url,'https://www.bilibili.com/video/BVParts/?p=2','multipart uses real p parameter');parts=[];
 location.pathname='/bangumi/play/ep1990';location.search='';modern=[199,200].map(n=>node({href:'https://www.bilibili.com/bangumi/play/ep'+(n*10),number:String(n),title:n+'会员'}));
 state=api.snapshot();assert.equal(state.episodes[0].number,199,'virtual list preserves real episode number');assert.equal(state.nextEpisode.title,'第 200 集');
 modern[1]=node({href:'https://www.bilibili.com/bangumi/play/ep2010',number:'201',title:'201会员'});assert.equal(api.nextEpisode(),null,'missing virtualized successor is not guessed');
 document.title='海绵宝宝 第4集-番剧-高清正版在线观看-bilibili-哔哩哔哩';assert.equal(api.snapshot().title,'海绵宝宝 第4集','strip website promotion from playback title');
 console.log('PASS: adapter login, seek, real playlist successors, end capture, trial and last-episode checks');
})().catch(error=>{console.error(error);process.exitCode=1});
