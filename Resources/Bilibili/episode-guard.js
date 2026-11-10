(()=>{
  if(!['www.bilibili.com','bilibili.com'].includes(location.hostname)||window.MacTVEpisodeGuard)return;
  window.MacTVEpisodeGuard={installed:true};
  const mainVideo=()=>[...document.querySelectorAll('video')].sort((a,b)=>b.clientWidth*b.clientHeight-a.clientWidth*a.clientHeight)[0];
  const playerPage=()=>/\/video\/|\/bangumi\/play\//.test(location.pathname);
  function holdEnd(event){
    const v=event.target;
    if(!playerPage()||v?.tagName!=='VIDEO'||v!==mainVideo())return;
    if(event.type!=='ended'&&(v.paused||v.seeking||v.readyState<2||!Number.isFinite(v.duration)||v.duration<=0||v.currentTime<v.duration-0.05))return;
    // Page-world capture runs before the site's target-level autoplay handlers.
    // MSE players may use their final timeupdate instead of a native ended event.
    v.setAttribute('data-mactv-ended','true');event.stopImmediatePropagation();v.pause();
  }
  document.addEventListener('ended',holdEnd,true);
  document.addEventListener('timeupdate',holdEnd,true);
  for(const name of ['playing','seeking'])document.addEventListener(name,event=>{
    const v=event.target;if(v?.tagName==='VIDEO'&&v.currentTime<Math.max(0,v.duration-1))v.removeAttribute('data-mactv-ended');
  },true);
})();
