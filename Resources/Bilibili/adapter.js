(()=>{
  if(!['www.bilibili.com','bilibili.com','search.bilibili.com'].includes(location.hostname))return;
  const elements=new Map(),identities=new WeakMap();let serial=0;
  const text=e=>(e?.textContent||'').replace(/\s+/g,' ').trim();
  const placed=e=>{const r=e.getBoundingClientRect();return r.width>0&&r.height>0;};
  const shown=e=>e?.isConnected&&placed(e)&&getComputedStyle(e).visibility!=='hidden';
  function id(e){if(!identities.has(e)){const value='b'+(++serial);identities.set(e,value);elements.set(value,e);}return identities.get(e);}
  function imageURL(img){let raw=img.currentSrc||img.getAttribute('data-src')||img.src||'';try{const u=new URL(raw,location.href);return u.protocol==='https:'&&/(^|\.)(hdslb\.com|biliimg\.com|bilibili\.com)$/.test(u.hostname)?u.href:'';}catch{return '';}}
  function cards(){
    const result=[],seen=new Set();
    for(const link of document.querySelectorAll('a[href*="/video/"],a[href*="/bangumi/play/"]')){
      let url;try{url=new URL(link.href,location.href);if(!/(^|\.)bilibili\.com$/.test(url.hostname))continue;}catch{continue;}
      const key=url.origin+url.pathname;if(seen.has(key))continue;
      const node=link.closest('.bili-video-card,.video-list-item,.video-item,.small-item,.bili-video-card__wrap,.bangumi-item')||link;
      const img=node.querySelector('img');if(!img||!placed(node))continue;
      const poster=imageURL(img);if(!poster||/广告|推广/.test(text(node).slice(0,12)))continue;
      const titleNode=node.querySelector('.bili-video-card__info--tit,.bili-video-card__info--tit a,.bili-video-card__info--title,h3,.title');
      const title=(text(titleNode)||titleNode?.getAttribute('title')||link.getAttribute('title')||img.alt||text(link)).replace(/<[^>]*>/g,'').trim();
      if(!title||title.length>180||/^(番剧|国创|综艺|纪录片|电影|电视剧)[\d.,万亿 ]*$/.test(title))continue;
      seen.add(key);result.push({id:id(link),title,poster});if(result.length>=300)break;
    }return result;
  }
  function episodeURL(raw){
    try{const u=new URL(raw,location.href);if(u.protocol!=='https:'||!['www.bilibili.com','bilibili.com'].includes(u.hostname)||!/^\/(bangumi\/play\/ep[0-9]+|video\/BV[A-Za-z0-9]+)\/?$/.test(u.pathname))return '';
      const p=u.searchParams.get('p');u.search='';u.hash='';if(p&&/^[1-9][0-9]*$/.test(p))u.searchParams.set('p',p);return u.href;
    }catch{return '';}
  }
  function episodes(){
    const modern=[...document.querySelectorAll('a[class*="EpisodeVirtualList_numberItem"],a[class*="EpisodeVirtualList_listItem"]')];
    const parts=[...document.querySelectorAll('#multi_page .list-box li')];
    const nodes=modern.length?modern:parts.length?parts:[...document.querySelectorAll('.video-pod__item')];
    const result=[],seen=new Set();
    for(const [index,el] of nodes.entries()){
      if(!placed(el))continue;
      const link=el.matches('a[href]')?el:el.querySelector('a[href]');
      const bvid=el.getAttribute('data-key')||'';
      let url=episodeURL(link?.href||(/^BV[A-Za-z0-9]+$/.test(bvid)?'https://www.bilibili.com/video/'+bvid+'/':''));
      let number=0;
      if(modern.length)number=Number(text(el.querySelector('[class*="numberTitle"]'))||el.getAttribute('title'));
      else if(parts.length){
        number=Number(text(el.querySelector('.index,.page-num,.episode-index')).replace(/\D/g,''));
        if(!number&&url)number=Number(new URL(url).searchParams.get('p'));
        if(!number)number=index+1;
        if(!url){const u=new URL(location.href);u.search='';u.searchParams.set('p',String(number));url=episodeURL(u.href);}
      } else number=index+1;
      if(!Number.isInteger(number)||number<1||!url||seen.has(url))continue;
      const label=text(el.querySelector('.title-txt,.title'))||text(el);
      if(!label||label.length>180)continue;seen.add(url);
      const here=new URL(location.href),there=new URL(url);
      const current=here.pathname.replace(/\/$/,'')===there.pathname.replace(/\/$/,'')&&(here.searchParams.get('p')||'1')===(there.searchParams.get('p')||'1');
      result.push({id:id(el),title:modern.length?'第 '+number+' 集':label,number,current,url});if(result.length>=300)break;
    }return result;
  }
  function nextEpisode(){
    const list=episodes(),index=list.findIndex(e=>e.current);if(index<0||index+1>=list.length)return null;
    const current=list[index],next=list[index+1];
    if(next.number!==current.number+1||next.url===current.url)return null;
    return {url:next.url,title:next.title};
  }
  function trialPlayback(){
    const v=video(),root=v?.closest('.bpx-player-container,#bilibili-player,.bilibili-player')||v?.parentElement;
    return /本片是大会员专享内容|试看结束|试看已结束|开通大会员.{0,20}继续观看/.test(text(root));
  }
  function ended(){const v=video();return !!v&&(v.ended||v.getAttribute('data-mactv-ended')==='true');}
  function advanceNext(expected){
    const target=nextEpisode();if(!ended()||trialPlayback()||!target||target.url!==expected)return false;
    location.assign(target.url);return true;
  }
  function video(){return [...document.querySelectorAll('video')].sort((a,b)=>b.clientWidth*b.clientHeight-a.clientWidth*a.clientHeight)[0];}
  function theatre(on){
    const old=document.querySelector('[data-mactv-theatre]');
    if(!on){old?.removeAttribute('data-mactv-theatre');document.querySelectorAll('[data-mactv-hidden]').forEach(e=>e.removeAttribute('data-mactv-hidden'));return;}
    const root=video()?.closest('.bpx-player-container,#bilibili-player,.bilibili-player')||video()?.parentElement;if(!root)return false;
    if(old&&old!==root)old.removeAttribute('data-mactv-theatre');root.setAttribute('data-mactv-theatre','');
    for(let p=root;p&&p!==document.body;p=p.parentElement){for(const sibling of p.parentElement?.children||[]){if(sibling!==p&&!/SCRIPT|STYLE|LINK/.test(sibling.tagName))sibling.setAttribute('data-mactv-hidden','');}}
    if(!document.getElementById('mactv-theatre-style')){const style=document.createElement('style');style.id='mactv-theatre-style';style.textContent='html:has([data-mactv-theatre]),body:has([data-mactv-theatre]){overflow:hidden!important;background:#000!important}[data-mactv-hidden]{visibility:hidden!important;pointer-events:none!important}[data-mactv-theatre]{position:fixed!important;inset:0!important;width:100vw!important;height:100vh!important;max-width:none!important;max-height:none!important;margin:0!important;z-index:2147480000!important;background:#000!important}[data-mactv-theatre] video{width:100%!important;height:100%!important;object-fit:contain!important}';document.head.appendChild(style);}
    document.documentElement.setAttribute('data-mactv-player-ready','');
    return true;
  }
  function playerReady(){
    const v=video();
    if(!v || theatre(true)!==true)return false;
    const rect=v.getBoundingClientRect();
    return v.readyState>=2 && rect.width>0 && rect.height>0;
  }
  function noDanmaku(){
    for(const notice of document.querySelectorAll('.bpx-player-container [class*="toast"],#bilibili-player [class*="toast"],.bpx-player-container [class*="ending"]')){
      if(/即将播放|已为您定位至|从头播放/.test(text(notice)))notice.setAttribute('data-mactv-native-notice','');
    }
    const toggle=document.querySelector('.bpx-player-dm-switch input[type="checkbox"]');if(toggle?.checked)toggle.click();
    for(const el of document.querySelectorAll('button,[aria-label],[title]')){if([el.getAttribute('aria-label'),el.title].some(s=>/^关闭弹幕/.test(s||''))&&placed(el))el.click();}
    if(!document.getElementById('mactv-no-danmaku')){const style=document.createElement('style');style.id='mactv-no-danmaku';style.textContent='[data-mactv-native-notice]{visibility:hidden!important;pointer-events:none!important}.bpx-player-dm-wrap,.bpx-player-dm-container,.bpx-player-dm-switch,.bpx-player-dm-input,[data-mactv-theatre] [class*="danmaku"],[data-mactv-theatre] [class*="danmu"],[data-mactv-theatre] [class*="barrage"]{visibility:hidden!important;pointer-events:none!important} [data-mactv-theatre] .bpx-player-sending-bar,[data-mactv-theatre] .bpx-player-control-wrap,[data-mactv-theatre] .bpx-player-top-wrap{display:none!important} [data-mactv-theatre] .bpx-player-primary-area{height:100%!important;background:#000!important}';document.head.appendChild(style);}
  }
  function qualityControl(){return document.querySelector('.bpx-player-ctrl-quality,.bilibili-player-video-btn-quality');}
  function prepareQuality(){
    const el=qualityControl();if(!el)return false;
    el.dispatchEvent(new MouseEvent('mouseenter',{bubbles:false}));el.dispatchEvent(new MouseEvent('mouseover',{bubbles:true}));return true;
  }
  function qualities(){
    const nodes=document.querySelectorAll('.bpx-player-ctrl-quality-menu-item,.bilibili-player-video-quality-menu li');
    return [...nodes].filter(e=>text(e)).map(e=>({id:id(e),title:text(e),current:/active|selected/.test(String(e.className))||e.getAttribute('aria-selected')==='true',restricted:/登录|大会员|会员|VIP/i.test(text(e))}));
  }
  function qualityLabel(){return text(document.querySelector('.bpx-player-ctrl-quality-result,.bilibili-player-video-btn-quality .bilibili-player-video-quality-menu-btn'));}
  function chooseQuality(key){
    const el=elements.get(key);if(!el?.isConnected||!el.matches('.bpx-player-ctrl-quality-menu-item,.bilibili-player-video-quality-menu li'))return {ok:false};
    el.click();return {ok:true};
  }
  function creator(){
    const root=document.querySelector('#v_upinfo,.up-info-container,.up-panel-container,.video-owner');
    const link=root?.querySelector('a[href*="space.bilibili.com"]');if(!link)return null;
    let u;try{u=new URL(link.href,location.href);}catch{return null;}
    const mid=u.pathname.split('/').find(Boolean);if(u.hostname!=='space.bilibili.com'||!/^\d+$/.test(mid||''))return null;
    const nameLink=root.querySelector('.up-name,.username,[class*="up-name"]');
    const img=root.querySelector('img');
    return {id:mid,name:text(nameLink)||link.getAttribute('title')||img?.alt||text(link)||'UP 主',avatar:img?imageURL(img):''};
  }
  function mediaTitle(){return String(text(document.querySelector('h1'))||document.title||'').replace(/[-_]番剧[-_].*$/,'').replace(/[-_]高清正版在线观看.*$/,'').replace(/_哔哩哔哩(?:_bilibili)?$/,'').replace(/[-_]bilibili[-_]哔哩哔哩$/,'');}
  function snapshot(debug=false){
    noDanmaku();const isPlayer=/\/video\/|\/bangumi\/play\//.test(location.pathname),v=video();if(isPlayer&&v)v.loop=false;
    const query=new URLSearchParams(location.search),keep=new URLSearchParams();for(const k of ['keyword','p'])if(query.has(k))keep.set(k,query.get(k));
    return {diagnostics:debug?{endState:{rawEnded:v?.ended,paused:v?.paused,seeking:v?.seeking,readyState:v?.readyState,networkState:v?.networkState,guardCaptured:v?.getAttribute('data-mactv-ended')==='true'},loginNodes:[...document.querySelectorAll('[class*="login"],[id*="login"]')].filter(e=>placed(e)).slice(0,35).map(e=>({tag:e.tagName,cls:String(e.className),id:e.id,text:text(e).slice(0,45),width:e.getBoundingClientRect().width,height:e.getBoundingClientRect().height})),frames:[...document.querySelectorAll('iframe')].map(e=>({title:e.title,host:(()=>{try{return new URL(e.src).host}catch{return ''}})(),width:e.clientWidth,height:e.clientHeight}))}:null,creator:isPlayer?creator():null,loggedIn:loginState(),url:location.origin+location.pathname+(keep.size?'?'+keep:''),title:mediaTitle(),isPlayer,cards:isPlayer?[]:cards(),episodes:isPlayer?episodes():[],ranges:[],ended:isPlayer&&ended(),trial:isPlayer&&trialPlayback(),nextEpisode:isPlayer?nextEpisode():null,qualities:isPlayer?qualities():[],qualityLabel:isPlayer?qualityLabel():'',hasVideo:!!v,paused:v?v.paused:true,current:v&&Number.isFinite(v.currentTime)?v.currentTime:0,duration:v&&Number.isFinite(v.duration)?v.duration:0};
  }
  function activate(key){
    const el=elements.get(key);if(!el?.isConnected||!placed(el))return false;
    const entry=episodes().find(e=>e.id===key);if(entry?.url){location.assign(entry.url);return true;}
    const link=el.matches('a[href]')?el:el.querySelector('a[href]');
    if(link){try{const url=new URL(link.href,location.href);if(/(^|\.)bilibili\.com$/.test(url.hostname)&&/\/video\/|\/bangumi\/play\//.test(url.pathname)){location.assign(url.href);return true;}}catch{}}
    theatre(false);el.click();theatre(true);return true;
  }
  async function media(action,position){const v=video();if(!v)return {ok:false,message:'播放器正在加载'};try{switch(action){case 'seek':if(Number.isFinite(position)&&Number.isFinite(v.duration)&&v.duration>0)v.currentTime=Math.min(v.duration,Math.max(0,position));break;case 'toggle':if(ended()){v.currentTime=0;v.removeAttribute('data-mactv-ended');await v.play();}else{v.paused?await v.play():v.pause();}break;case 'play':if(ended()){v.currentTime=0;v.removeAttribute('data-mactv-ended');}await v.play();break;case 'pause':v.pause();break;case 'left':v.currentTime=Math.max(0,v.currentTime-10);break;case 'right':v.currentTime=Math.min(v.duration||Infinity,v.currentTime+10);break;case 'skipForward':v.currentTime+=30;break;case 'skipBackward':v.currentTime=Math.max(0,v.currentTime-30);break;case 'volumeUp':v.muted=false;v.volume=Math.min(1,v.volume+.05);break;case 'volumeDown':v.volume=Math.max(0,v.volume-.05);break;case 'mute':v.muted=!v.muted;}return {ok:true,current:Number.isFinite(v.currentTime)?v.currentTime:0,duration:Number.isFinite(v.duration)?v.duration:0,paused:v.paused};}catch{return {ok:false,message:'站点暂未允许此操作'};}}
  function loginState(){
    const entry=document.querySelector('.header-login-entry');
    const avatar=document.querySelector('.header-avatar-wrap img,.header-entry-mini img');
    // Cinema mode hides the header visually, but its account markup remains valid.
    if(avatar&&placed(avatar)&&(!entry||!placed(entry)))return true;
    if(entry&&placed(entry)&&/登录/.test(text(entry)))return false;
    return null;
  }
  function loggedIn(){return loginState()===true;}
  function loginInfo(){
    if(loggedIn())return {loggedIn:true};
    const selectors=['.login-scan-wp','.login-scan-box','.bili-mini-login-wrap','.bili-mini-login','iframe[src*="login"]'];
    for(const selector of selectors)for(const el of document.querySelectorAll(selector)){if(!shown(el))continue;const r=el.getBoundingClientRect();if(r.width<160||r.height<160)continue;return {loggedIn:false,x:Math.max(0,r.left),y:Math.max(0,r.top),width:Math.min(innerWidth-r.left,r.width),height:Math.min(innerHeight-r.top,r.height)};}
    return {loggedIn:false};
  }
  let lastLoginClick=0;
  function showLogin(){
    if(loginInfo().width||loggedIn())return true;if(Date.now()-lastLoginClick<2500)return false;
    const direct=document.querySelector('.header-login-entry .default-login')||document.querySelector('.header-login-entry .header-avatar-wrap');
    const options=[...document.querySelectorAll('button,a,span,div')].filter(e=>{if(!shown(e)||!/^(登录|立即登录|登录\/注册)$/.test(text(e)))return false;const r=e.getBoundingClientRect();return r.width>=15&&r.width<220&&r.height>=10&&r.height<100;}).sort((a,b)=>a.clientWidth*a.clientHeight-b.clientWidth*b.clientHeight);
    const el=direct||options[0]||document.querySelector('.header-login-entry');if(!el)return false;lastLoginClick=Date.now();el.click();return true;
  }

  function closeLogin(){const el=document.querySelector('.bili-mini-close-icon,.bili-mini-login-close,.bili-mini-mask [class*="close"]');el?.click();return true;}
  window.MacTVBilibili={snapshot,activate,media,theatre,playerReady,nextEpisode,advanceNext,prepareQuality,chooseQuality,loginInfo,showLogin,closeLogin,more:()=>{window.scrollBy(0,innerHeight*.85);return true;}};
})();
