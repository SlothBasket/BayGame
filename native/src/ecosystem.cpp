#include "ecosystem.hpp"
namespace bay {
using Clock=std::chrono::steady_clock;
static double seconds(Clock::duration d){return std::chrono::duration<double>(d).count();}
static int64_t key(int x,int y){return int64_t(uint64_t(uint32_t(x))<<32|uint32_t(y));}
bool Engine::wet(V p)const{int x=int(std::floor((p.x-origin.x)/cell)),y=int(std::floor((p.y-origin.y)/cell));return x>=0&&y>=0&&x<width&&y<height&&water[size_t(y)*width+x]!=0;}
bool Engine::clear(V a,V b)const{
 V d=b-a; int x=int(std::floor((a.x-origin.x)/cell)),y=int(std::floor((a.y-origin.y)/cell)),ex=int(std::floor((b.x-origin.x)/cell)),ey=int(std::floor((b.y-origin.y)/cell));
 int sx=d.x>0?1:-1,sy=d.y>0?1:-1;double tx=d.x!=0?(origin.x+(x+(sx>0))*cell-a.x)/d.x:INFINITY,ty=d.y!=0?(origin.y+(y+(sy>0))*cell-a.y)/d.y:INFINITY,dx=d.x!=0?cell/std::abs(d.x):INFINITY,dy=d.y!=0?cell/std::abs(d.y):INFINITY;
 auto w=[&](int xx,int yy){return xx>=0&&yy>=0&&xx<width&&yy<height&&water[size_t(yy)*width+xx]!=0;};
 for(int n=std::abs(ex-x)+std::abs(ey-y)+4;n-->0;){if(!w(x,y))return false;if(x==ex&&y==ey)return true;if(std::abs(tx-ty)<1e-8){if(!w(x+sx,y)||!w(x,y+sy))return false;x+=sx;y+=sy;tx+=dx;ty+=dy;}else if(tx<ty){x+=sx;tx+=dx;}else{y+=sy;ty+=dy;}}return false;
}
int Engine::nearest(V at,int component)const{
 int cx=int(std::floor(at.x/256)),cy=int(std::floor(at.y/256)),best=-1;double dist=INFINITY;
 for(int ring=0;ring<5;ring++){for(int y=-ring;y<=ring;y++)for(int x=-ring;x<=ring;x++){if(ring&&std::abs(x)!=ring&&std::abs(y)!=ring)continue;auto it=node_cells.find(key(cx+x,cy+y));if(it==node_cells.end())continue;for(auto i:it->second){auto const& n=nodes[i];if(component>=0&&n.component!=component)continue;double d=(n.at-at).len2();if(d<dist&&clear(at,n.at)){best=int(i);dist=d;}}}if(best>=0&&dist<(ring*256.0)*(ring*256.0))break;}return best;
}
double Engine::bed(V at,int node)const{int n=nearest(at,node>=0?nodes[node].component:-1);return std::max(.1,(n>=0?nodes[n].depth:2)+controls.tide);}
V Engine::sample(int node,double radius){if(node<0||node>=int(nodes.size()))return{};for(int n=0;n<8;n++){double t=random()*6.28318530718;V p=nodes[node].at+V{std::cos(t),std::sin(t)}*(std::sqrt(random())*radius);if(clear(nodes[node].at,p))return p;}return nodes[node].at;}
V Engine::position(Animal const& a,double time)const{
 if(a.path.size()<2)return a.at;double distance=clamp((time-a.route_started)*a.route_speed,0,a.route_length);auto it=std::lower_bound(a.lengths.begin()+1,a.lengths.end(),distance);size_t i=std::min(size_t(it-a.lengths.begin()),a.path.size()-1);double f=(distance-a.lengths[i-1])/std::max(1e-9,a.lengths[i]-a.lengths[i-1]);return a.path[i-1]+(a.path[i]-a.path[i-1])*clamp(f,0,1);
}
void Engine::advance(Animal& a,double time){V previous=a.at;a.at=position(a,time);double dt=std::max(0.0,time-a.last);if(dt>0&&(a.at-previous).len2()>1e-10)a.velocity=(a.at-previous)*(1/dt);double rate=(a.kind==1?.25:.4);a.depth+=clamp(a.target_depth-a.depth,-rate*dt,rate*dt);a.depth=clamp(a.depth,0,std::max(.02,a.bottom-.02));}
void Engine::route(Animal& a,V goal,int target_node,double speed){
 auto begin=Clock::now();++route_count;V start=a.at;a.path.clear();a.lengths.clear();a.path.push_back(start);
 if(clear(start,goal))a.path.push_back(goal);
 else{
 int from=nearest(start,a.node>=0?nodes[a.node].component:-1);int to=target_node>=0?target_node:nearest(goal,from>=0?nodes[from].component:-1);
 if(from>=0&&to>=0&&nodes[from].component==nodes[to].component){
 ++search_stamp;if(search_stamp==0){std::fill(visited.begin(),visited.end(),0);++search_stamp;}using Q=std::pair<double,int>;std::priority_queue<Q,std::vector<Q>,std::greater<Q>> q;visited[from]=search_stamp;costs[from]=0;parents[from]=-1;q.push({0,from});int expanded=0;
 while(!q.empty()&&expanded++<12000){int n=q.top().second;q.pop();if(n==to)break;for(int next:nodes[n].neighbors){if(next<0||next>=int(nodes.size()))continue;double c=costs[n]+(nodes[n].at-nodes[next].at).len();if(visited[next]!=search_stamp||c<costs[next]){visited[next]=search_stamp;costs[next]=c;parents[next]=n;q.push({c+(nodes[next].at-nodes[to].at).len(),next});}}}
 if(visited[to]==search_stamp){std::vector<int> reversed;for(int n=to;n>=0;n=parents[n]){reversed.push_back(n);if(n==from)break;}if(!reversed.empty()&&reversed.back()==from){for(auto it=reversed.rbegin();it!=reversed.rend();++it)a.path.push_back(nodes[*it].at);if(clear(a.path.back(),goal))a.path.push_back(goal);}}
 }}
 a.lengths.push_back(0);for(size_t i=1;i<a.path.size();i++)a.lengths.push_back(a.lengths.back()+(a.path[i]-a.path[i-1]).len());a.route_length=a.lengths.back();a.route_started=sim;a.route_speed=std::max(0.0,speed);nav_total+=seconds(Clock::now()-begin)*1000;
}
void Engine::remove_occupancy(uint32_t slot){auto& a=animals[slot];for(auto k:a.cells){auto it=spatial.find(k);if(it==spatial.end())continue;auto& list=it->second;auto found=std::find(list.begin(),list.end(),slot);if(found!=list.end()){*found=list.back();list.pop_back();}if(list.empty())spatial.erase(it);}a.cells.clear();}
void Engine::occupancy(uint32_t slot){auto& a=animals[slot];V lo=a.at,hi=a.at;double horizon=interval(a.tier);if(a.target.slot!=UINT32_MAX)horizon=std::min(horizon,2.0);V end=position(a,sim+horizon);lo={std::min(lo.x,end.x),std::min(lo.y,end.y)};hi={std::max(hi.x,end.x),std::max(hi.y,end.y)};double limit=(sim+horizon-a.route_started)*a.route_speed;
 for(size_t i=0;i<a.path.size();i++){if(i&&a.lengths[i-1]>limit)break;if(a.lengths[i]+1e-6<(sim-a.route_started)*a.route_speed)continue;lo={std::min(lo.x,a.path[i].x),std::min(lo.y,a.path[i].y)};hi={std::max(hi.x,a.path[i].x),std::max(hi.y,a.path[i].y)};}
 int x0=int(std::floor(lo.x/128)),y0=int(std::floor(lo.y/128)),x1=int(std::floor(hi.x/128)),y1=int(std::floor(hi.y/128));if(a.cells.size()==size_t((x1-x0+1)*(y1-y0+1))&&!a.cells.empty()&&a.cells.front()==key(x0,y0)&&a.cells.back()==key(x1,y1))return;
 remove_occupancy(slot);for(int y=y0;y<=y1;y++)for(int x=x0;x<=x1;x++){auto k=key(x,y);spatial[k].push_back(slot);a.cells.push_back(k);}
}
void Engine::query(V at,double radius,std::vector<uint32_t>& result){result.clear();++query_count;if(++query_stamp==0){std::fill(query_marks.begin(),query_marks.end(),0);++query_stamp;}int x0=int(std::floor((at.x-radius)/128)),x1=int(std::floor((at.x+radius)/128)),y0=int(std::floor((at.y-radius)/128)),y1=int(std::floor((at.y+radius)/128));for(int y=y0;y<=y1;y++)for(int x=x0;x<=x1;x++){auto it=spatial.find(key(x,y));if(it==spatial.end())continue;for(auto slot:it->second){if(query_marks[slot]==query_stamp)continue;query_marks[slot]=query_stamp;if(animals[slot].alive&&(position(animals[slot],sim)-at).len2()<=radius*radius)result.push_back(slot);}}}
int Engine::detail(Animal const& a)const{if(!controls.lod||code(a)==controls.selected||a.threat_until>sim)return 0;V at=position(a,sim);double d=std::min((at-controls.boat).len2(),(at-controls.camera).len2());if(d<std::pow(controls.detailed+(a.tier==0?controls.hysteresis:0),2))return 0;if(d<std::pow(controls.intermediate+(a.tier<2?controls.hysteresis:0),2))return 1;return 2;}
double Engine::interval(int tier)const{return tier==0?.2:(tier==1?2:12);}
void Engine::schedule(uint32_t slot,double at){auto& a=animals[slot];a.due=at;++a.token;events.push({at,slot,a.generation,a.token});}
void Engine::plan(Animal& a){
 if(a.node<0)a.node=nearest(a.at);if(a.node<0)return;int destination=a.node;
 bool ambush=a.profile.style==1||a.profile.style==2;bool rock=a.kind==0&&a.species==7&&a.size>=43.18;
 if(a.kind!=1&&(a.energy<.2||a.hunger<.08)){a.state=9;destination=a.home>=0?a.home:a.node;}else if(rock){destination=a.home>=0?a.home:a.node;a.state=4;}else{
 double best=-1e9;std::vector<int> options=nodes[a.node].neighbors;options.push_back(a.node);if(a.feeding>=0&&nodes[a.feeding].component==nodes[a.node].component)options.push_back(a.feeding);if(a.home>=0&&nodes[a.home].component==nodes[a.node].component)options.push_back(a.home);
 for(int n:options){double score=nodes[n].food+nodes[n].cover*(ambush?.8:.2)+random()*.55-std::abs(nodes[n].depth-a.holding)*.04;if(n==a.feeding)score+=.15;if(score>best){best=score;destination=n;}}
 a.state=ambush?4:0;}
 V goal=rock?a.home_at+V{random()*12-6,random()*12-6}:sample(destination,a.kind==1?18:35);if(rock&&!clear(nodes[destination].at,goal))goal=sample(destination,8);
 double velocity=a.kind==1?(a.species==4||a.species==5?.05:.4):a.profile.cruise;if(a.state==9)velocity*=.35;route(a,goal,destination,velocity);a.decision=sim+(a.kind==1?45:(ambush?35:25))+random()*35;a.feeding=destination;
}
void Engine::steer(Animal& a,V goal,double dt,double speed){
 V wanted=(goal-a.at).unit()*speed;double acceleration=(a.kind==1?2.5:1.8)*dt;V change=wanted-a.velocity;if(change.len()>acceleration)change=change.unit()*acceleration;a.velocity=a.velocity+change;V next=a.at+a.velocity*dt;
 if(clear(a.at,next)){route(a,next,-1,dt>0?(next-a.at).len()/dt:0);a.at=next;a.path.clear();a.lengths.clear();a.route_length=0;}else if(a.path.size()<2||sim>a.route_started+a.route_length/std::max(.1,a.route_speed))route(a,goal,-1,speed);
}
void Engine::retire(uint32_t slot){auto& a=animals[slot];if(!a.alive)return;a.alive=false;a.quantity=0;++a.token;remove_occupancy(slot);if(a.kind==1){bait_ids.erase(a.id);if(a.temporary){auto it=bait_ids.find(a.parent_id);if(it!=bait_ids.end())animals[it->second].escapees=std::max(0,animals[it->second].escapees-1);}free_bait.push_back(slot);}a.event=4;}
bool Engine::eat(uint32_t slot){auto& a=animals[slot];if(!a.alive||a.quantity<=0)return false;--a.quantity;++consumed;if(a.quantity==0)retire(slot);return true;}
uint32_t Engine::add_bait(Animal a){uint32_t slot;int index;if(!free_bait.empty()){slot=free_bait.back();free_bait.pop_back();index=animals[slot].index;a.generation=animals[slot].generation+1;animals[slot]=std::move(a);}else{index=0;for(auto const& item:animals)if(item.kind==1)index=std::max(index,item.index+1);if(index>=24000)return UINT32_MAX;slot=uint32_t(animals.size());animals.push_back(std::move(a));query_marks.push_back(0);}auto& item=animals[slot];item.kind=1;item.index=index;item.id=next_bait_id++;item.alive=true;item.last=sim;item.path.clear();item.cells.clear();item.token=0;item.tier=detail(item);bait_ids[item.id]=slot;code_slots[code(item)]=slot;occupancy(slot);schedule(slot,sim+.2);return slot;}
void Engine::scatter(uint32_t slot,V threat){auto& a=animals[slot];if(!a.alive)return;a.threat=threat;a.threat_until=sim+3;a.fear=std::min(1.0,a.fear+.3);a.spread=std::min(1.5,a.spread+.25);a.event=2;
 if(a.kind!=1||a.individual||a.tier!=0||sim<a.scatter_at)return;a.scatter_at=sim+4;for(int n=0;n<2&&a.escapees<6&&a.quantity>1;n++){Animal child=a;child.temporary=true;child.individual=true;child.parent_id=a.id;child.quantity=child.capacity=1;child.escapees=0;child.target={};child.hunger=0;child.state=10;child.detached_at=sim;child.regroup_at=sim+3;child.spread=0;V offset=V{random()*4-2,random()*4-2};if(clear(child.at,child.at+offset))child.at=child.at+offset;uint32_t created=add_bait(std::move(child));if(created==UINT32_MAX)break;--a.quantity;++a.escapees;++detached;}}
void Engine::attack(uint32_t slot){auto& a=animals[slot];if(!valid(a.target))return;auto& prey=animals[a.target.slot];advance(prey,sim);double vertical=std::abs(a.depth-prey.depth),distance=(a.at-prey.at).len();if(distance>a.profile.reach||vertical>a.profile.reach||sim<a.attack_at)return;
 ++a.attempts;a.attack_at=sim+a.profile.cooldown;a.energy=std::max(0.0,a.energy-.025);bool ambush=a.profile.style==1||a.profile.style==2;double chance=a.profile.chance+(ambush?.22:.06)*(1-prey.fear)+.18*(a.energy-.5)+.12*(.35-prey.size/std::max(1.0,a.size))-.18*(prey.node>=0?nodes[prey.node].cover:.1)-.10*prey.fear-.06*clamp(prey.velocity.len()/std::max(.1,a.profile.burst),0,1)+std::min(.12,(sim-a.pursuit_started)*.003)-.10*vertical/std::max(.1,a.profile.reach);chance=clamp(chance,.15,.95);
 if(random()<chance&&eat(a.target.slot)){++a.captures;a.state=8;a.until=sim+a.profile.consume;a.hunger=std::max(0.0,a.hunger-clamp(.10+prey.size/a.size*1.3,.10,.75));a.event=1;if(a.kind==0)a.size+=std::min(.02,prey.size*.002);if(prey.alive)scatter(a.target.slot,a.at);a.target={};}
 else{++a.misses;a.energy=std::max(0.0,a.energy-.035);a.event=3;scatter(a.target.slot,a.at);}
}
void Engine::hunt(uint32_t slot,double dt){auto& a=animals[slot];bool ambush=a.profile.style==1||a.profile.style==2;
 if(a.threat_until>sim){a.state=10;V goal=a.at+(a.at-a.threat).unit()*12;if(a.tier==0)steer(a,goal,dt,a.profile.burst);else route(a,goal,-1,a.profile.burst);a.target={};return;}
 if(a.state==8&&sim<a.until){a.energy=std::min(1.0,a.energy+dt*.005);return;}
 if(a.energy<.15||a.hunger<.08){a.state=9;a.target={};a.energy=std::min(1.0,a.energy+dt*.025);if(sim>=a.decision)plan(a);return;}
 if(valid(a.target)){
 auto& prey=animals[a.target.slot];V target=position(prey,sim);double distance=(target-a.at).len();if(distance>a.profile.detect*3||sim-a.pursuit_started>75){a.target={};a.detect_at=sim+3;a.decision=sim;return;}
 if(a.kind==0&&a.species==7&&a.size>=43.18&&(a.at-a.home_at).len()>25){a.target={};route(a,a.home_at,a.home,a.profile.cruise);a.detect_at=sim+4;return;}
 a.target_depth=clamp(prey.depth,0,a.bottom-.02);if(ambush&&distance>a.profile.lunge&&sim-a.pursuit_started<6){a.state=4;return;}a.state=3;
 if(a.tier==0){V intercept=target+prey.velocity*std::min(2.0,distance/std::max(.1,a.profile.burst)*.4);if(!clear(target,intercept))intercept=target;steer(a,intercept,dt,a.profile.burst);if(distance<a.profile.detect*.7){prey.threat=a.at;prey.threat_until=sim+3;prey.fear=std::min(1.0,prey.fear+.08);if(prey.due>sim+.2)schedule(a.target.slot,sim+.2);}}
 else if(sim>=a.detect_at){route(a,target+prey.velocity*std::min(3.0,distance/std::max(.1,a.profile.burst)),-1,a.profile.burst);a.detect_at=sim+3;}
 a.energy=std::max(0.0,a.energy-dt*.0015);attack(slot);return;}
 a.target={};if(sim>=a.detect_at){a.detect_at=sim+(a.tier==0?1:(a.tier==1?5:20));thread_local std::vector<uint32_t> candidates;candidates.reserve(256);query(a.at,a.profile.detect,candidates);double best=-1e9;Handle chosen;
 for(auto i:candidates){auto const& prey=animals[i];if(i==slot||prey.kind==2||prey.size>=a.size*a.profile.gape||prey.quantity<1||(prey.kind==0&&prey.species==a.species&&prey.size>a.size*.3))continue;if(a.profile.style==3&&prey.kind!=3&&!(prey.kind==1&&(prey.species==4||prey.species==5)))continue;V at=position(prey,sim);double distance=(at-a.at).len(),vertical=std::abs(prey.depth-a.depth);if(vertical>a.profile.detect*.5)continue;double score=prey.size*.1-distance*.06+(prey.temporary?.8:0)+(prey.fear*.2);if(score>best&&clear(a.at,at)){best=score;chosen=handle(i);}}
 if(valid(chosen)){a.target=chosen;a.pursuit_started=sim;a.state=ambush?4:2;a.event=5;return;}}
 a.energy=std::min(1.0,a.energy+dt*.002);if(sim>=a.decision||a.path.empty())plan(a);
}
void Engine::bait(uint32_t slot,double dt){auto& a=animals[slot];a.fear=std::max(0.0,a.fear-dt*.05);a.spread=std::max(.05,a.spread-dt*.02);
 if(a.temporary||a.individual){a.hunger=0;
 if(a.threat_until>sim){a.state=10;a.regroup_at=sim+2;V goal=a.at+(a.at-a.threat).unit()*12+V{random()-.5,random()-.5}*3;a.target_depth=clamp(a.depth+(random()-.5),0,a.bottom-.02);if(a.tier==0)steer(a,goal,dt,1.3);else if(sim>=a.decision){route(a,goal,-1,1.3);a.decision=sim+3;}return;}
 if(sim<a.regroup_at)return;auto parent=bait_ids.find(a.parent_id);uint32_t parent_slot=parent==bait_ids.end()?UINT32_MAX:parent->second;
 if(parent_slot==UINT32_MAX&&sim>=a.detect_at){a.detect_at=sim+10;thread_local std::vector<uint32_t> nearby;query(a.at,100,nearby);double closest=1e9;for(auto i:nearby){auto const& b=animals[i];if(b.kind!=1||b.individual||b.species!=a.species)continue;double d=(position(b,sim)-a.at).len2();if(d<closest){closest=d;parent_slot=i;}}if(parent_slot!=UINT32_MAX)a.parent_id=animals[parent_slot].id;}
 if(parent_slot!=UINT32_MAX&&animals[parent_slot].alive){auto& parent_school=animals[parent_slot];V goal=position(parent_school,sim);a.state=11;a.target_depth=parent_school.depth;
 if((goal-a.at).len()<3&&std::abs(a.depth-parent_school.depth)<.6&&parent_school.threat_until<=sim){++parent_school.quantity;parent_school.capacity=std::max(parent_school.capacity,parent_school.quantity);++rejoined;retire(slot);return;}
 if(a.tier==0)steer(a,goal,dt,.8);else if(sim>=a.decision||a.path.empty()||(a.path.back()-goal).len()>12){route(a,goal,parent_school.node,.8);a.decision=sim+5;}}
 else{a.state=9;if(sim>=a.decision){V goal=sample(a.node,8);route(a,goal,a.node,.2);a.decision=sim+20;}}return;}
 if(a.threat_until>sim){a.state=10;if(sim>=a.decision){V goal=a.at+(a.at-a.threat).unit()*(a.fear>.85?50:10);route(a,goal,-1,a.fear>.85?1.2:.5);a.decision=sim+4;}scatter(slot,a.threat);return;}
 a.state=0;if(sim>=a.decision)plan(a);
}
void Engine::update(uint32_t slot){auto& a=animals[slot];if(!a.alive)return;double dt=std::max(0.0,sim-a.last);advance(a,sim);a.tier=detail(a);
 if(a.node<0||(a.at-nodes[a.node].at).len()>100){int n=nearest(a.at,a.node>=0?nodes[a.node].component:-1);if(n>=0){a.node=n;a.zone=nodes[n].zone;}}
 a.bottom=std::max(.1,(a.node>=0?nodes[a.node].depth:2)+controls.tide);double ratio=a.kind==1?(a.species==4||a.species==5?.95:(a.species==0?.15:.45)):(a.species==3||a.species==6?.94:(a.species==0?.8:.5));a.holding=clamp(a.bottom*ratio+std::sin(sim*.015+double(a.id%1000))*.15,0,a.bottom-.02);if(!valid(a.target))a.target_depth=a.holding;
 if(a.kind==3){a.quantity=std::min(a.capacity,a.quantity+int(dt*.1));}
 else if(a.kind==1)bait(slot,dt);
 else{a.hunger=clamp(a.hunger+dt*.00006*clamp(60/std::max(20.0,a.size),.5,1.5),0,1);hunt(slot,dt);}
 a.last=sim;if(!a.alive)return;occupancy(slot);double delay=a.kind==3?30:interval(a.tier);if(valid(a.target)&&a.tier>0)delay=std::min(delay,3.0);if(a.path.size()>1&&a.route_speed>0){double arrival=a.route_started+a.route_length/a.route_speed;if(arrival>sim+.01)delay=std::min(delay,arrival-sim);}
 if(a.tier>0){double distance=std::min((a.at-controls.boat).len(),(a.at-controls.camera).len()),boundary=a.tier==2?controls.intermediate:controls.detailed;if(a.route_speed>0)delay=std::min(delay,std::max(.2,(distance-boundary)/a.route_speed));}
 schedule(slot,sim+std::max(.1,delay));++event_count;
}
void Engine::start(uint64_t seed){stop();rng.seed(seed);stopping=false;animals.reserve(animals.size()+24000);query_marks.resize(animals.size());costs.resize(nodes.size());parents.resize(nodes.size());visited.resize(nodes.size());
 for(uint32_t i=0;i<nodes.size();i++)node_cells[key(int(std::floor(nodes[i].at.x/256)),int(std::floor(nodes[i].at.y/256)))].push_back(i);
 for(uint32_t i=0;i<animals.size();i++){auto& a=animals[i];code_slots[code(a)]=i;if(a.kind==1){bait_ids[a.id]=i;next_bait_id=std::max(next_bait_id,a.id+1);}a.node=nearest(a.at);if(a.node>=0){a.zone=nodes[a.node].zone;a.bottom=nodes[a.node].depth;}a.home_at=a.at;a.tier=detail(a);occupancy(i);schedule(i,.1+random()*interval(a.tier));}publish();worker=std::thread(&Engine::loop,this);}
void Engine::stop(){stopping=true;cv.notify_all();if(worker.joinable())worker.join();}
void Engine::control(Controls const& c){{std::lock_guard<std::mutex> lock(mutex);requested_controls=c;}cv.notify_all();}
void Engine::spawn(int species,V at){{std::lock_guard<std::mutex> lock(mutex);commands.push_back({0,species,at});}cv.notify_all();}
void Engine::publish(){auto snap=std::make_shared<Snapshot>();snap->rows.reserve(animals.size());snap->time=sim;snap->requested=requested;snap->cpu_ms=cpu_total;snap->wall=wall_total;snap->achieved=wall_total>0?sim/wall_total:0;snap->events=event_count;snap->consumed=consumed;snap->detached=detached;snap->rejoined=rejoined;snap->queries=query_count;snap->routes=route_count;snap->nav_ms=nav_total;snap->memory=animals.capacity()*sizeof(Animal)+water.size();
 for(auto const& a:animals){Row r{};r.code=code(a);r.kind=a.kind;r.index=a.index;r.id=a.id;r.generation=a.generation;r.species=a.species;r.state=a.state;r.tier=a.tier;r.zone=a.zone;r.school=a.school;r.quantity=a.quantity;r.escapees=a.escapees;r.captures=a.captures;r.misses=a.misses;r.attempts=a.attempts;r.parent_id=a.parent_id;r.alive=a.alive;r.temporary=a.temporary;r.individual=a.individual;r.at=position(a,sim);r.velocity=a.velocity;r.destination=a.path.empty()?a.at:a.path.back();r.depth=a.depth;r.holding=a.holding;r.target_depth=a.target_depth;r.bottom=a.bottom;r.size=a.size;r.hunger=a.hunger;r.energy=a.energy;r.fear=a.fear;r.spread=a.spread;r.target_code=valid(a.target)?code(animals[a.target.slot]):-1;r.target_id=valid(a.target)?animals[a.target.slot].id:0;r.event=a.event;r.home=a.home;r.feeding=a.feeding;snap->rows.push_back(r);if(a.alive){++snap->alive[a.kind];if(a.kind<3)++snap->counts[a.tier];}}
 std::atomic_store(&published,std::shared_ptr<const Snapshot>(snap));}
void Engine::loop(){auto last=Clock::now(),published_at=last;V previous_boat{INFINITY,INFINITY},previous_camera=previous_boat;int previous_selected=-2;
 while(!stopping){auto now=Clock::now();double wall=seconds(now-last);last=now;wall_total+=wall;std::vector<Command> batch;{std::lock_guard<std::mutex> lock(mutex);controls=requested_controls;batch.swap(commands);}requested+=wall*std::max(0.0,controls.speed);
 auto begin=Clock::now();for(auto cmd:batch){if(!wet(cmd.at))continue;Animal a;a.kind=1;a.species=cmd.species;a.individual=true;a.hunger=0;a.at=cmd.at;a.node=nearest(a.at);a.home=a.feeding=a.node;a.size=cmd.species==5?3:6;a.depth=.5;add_bait(std::move(a));}
 if((controls.boat-previous_boat).len2()>2500||(controls.camera-previous_camera).len2()>2500||controls.selected!=previous_selected){previous_boat=controls.boat;previous_camera=controls.camera;previous_selected=controls.selected;std::vector<uint32_t> nearby;query(controls.boat,controls.intermediate+controls.hysteresis,nearby);std::vector<uint32_t> camera_near;query(controls.camera,controls.intermediate+controls.hysteresis,camera_near);nearby.insert(nearby.end(),camera_near.begin(),camera_near.end());auto selected=code_slots.find(controls.selected);if(selected!=code_slots.end())nearby.push_back(selected->second);for(auto i:nearby)if(animals[i].due>sim+.2&&detail(animals[i])<animals[i].tier)schedule(i,sim+.2);}
 if(controls.speed>0){while(!events.empty()&&events.top().at<=requested&&!stopping&&seconds(Clock::now()-begin)*1000<clamp(controls.cpu_ms,1,40)){Event e=events.top();events.pop();if(e.slot>=animals.size())continue;auto& a=animals[e.slot];if(!a.alive||a.generation!=e.generation||a.token!=e.token)continue;sim=std::max(sim,e.at);update(e.slot);}if(events.empty()||events.top().at>requested)sim=requested;}
 cpu_total+=seconds(Clock::now()-begin)*1000;if(seconds(Clock::now()-published_at)>=.05){publish();published_at=Clock::now();}
 if(events.size()>animals.size()*3){std::priority_queue<Event> compact;for(uint32_t i=0;i<animals.size();i++){auto const& a=animals[i];if(a.alive)compact.push({a.due,i,a.generation,a.token});}events.swap(compact);}
 std::unique_lock<std::mutex> lock(mutex);cv.wait_for(lock,std::chrono::milliseconds(5),[&]{return stopping.load()||!commands.empty();});}
 publish();}
}
