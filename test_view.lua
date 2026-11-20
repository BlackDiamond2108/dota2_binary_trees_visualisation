local project = (arg[0]:match('^(.*)/') or '.')
dofile(project .. '/addon/scripts/vscripts/tree_view.lua')
local callbacks={}
GameRules={GetGameModeEntity=function()return {SetContextThink=function(_,name,fn)callbacks[name]=fn end}end}
TreeView.units={};TreeView.pendingDeaths={};TreeView.incident={};TreeView.edges={};TreeView.queue={};TreeView.visual={}
local nextCount=0
local realNext=TreeView.Next
function TreeView:Next() nextCount=nextCount+1 end
function TreeView:Say() end
for i=1,300 do TreeView:DeleteDeadKey(tostring(i));TreeView:DeleteDeadKey(tostring(i)) end
assert(#TreeView.queue==1 and #TreeView.queue[1].keys==300 and not TreeView.queue[1].ready)
callbacks.BSTDeathBatch();assert(TreeView.queue[1].ready and nextCount==1)
TreeView:DeleteDeadKey('301');TreeView:Request('insert/999');TreeView:DeleteDeadKey('302')
assert(#TreeView.queue==4 and TreeView.queue[2].ready and TreeView.queue[3].endpoint=='insert/999')
assert(TreeView.queue[4].keys[1]=='302')
callbacks.BSTDeathBatch();assert(TreeView.queue[4].ready)
local vectorMeta={__add=function(a,b)return setmetatable({x=a.x+b.x,y=a.y+b.y,z=a.z+b.z},getmetatable(a))end}
function Vector(x,y,z)return setmetatable({x=x,y=y,z=z},vectorMeta)end
function GetGroundHeight()return 0 end
local created,destroyed,moves=0,0,0
ParticleManager={CreateParticle=function()created=created+1;return created end,SetParticleControlEnt=function()end,DestroyParticle=function()destroyed=destroyed+1 end,ReleaseParticleIndex=function()end}
function CreateUnitByName(_,pos)
 return {pos=pos,IsNull=function(self)return self.removed end,IsAlive=function(self)return not self.dead end,SetModelScale=function()end,SetAbsOrigin=function(self,p)self.pos=p;moves=moves+1 end,SetCustomHealthLabel=function()end,SetRenderColor=function()end,GetAbsOrigin=function(self)return self.pos end}
end
function UTIL_Remove(u)u.removed=true end
TreeView.units={};TreeView.pendingDeaths={};TreeView.incident={};TreeView.edges={};TreeView.queue={};TreeView.visual={};TreeView.openDeathBatch=nil;TreeView.origin=Vector(0,0,0)
local snapshot='BST1 3 ready\n1 2 0 1 0\n2 none 1 0 0\n3 2 2 1 0\n'
TreeView:Render(snapshot);assert(created==2 and destroyed==0)
local stable=TreeView.edges['3'].particle;local oldMoves=moves
TreeView:Render(snapshot);assert(created==2 and destroyed==0 and moves==oldMoves)
TreeView.units['1'].dead=true;TreeView:DeleteDeadKey('1')
assert(destroyed==1 and TreeView.edges['3'].particle==stable)
TreeView:Complete({endpoint='delete_many',keys={'1'}},'BST1 2 deleted_batch\n2 none 0 0 0\n3 2 1 1 0\n')
assert(created==2 and destroyed==1 and TreeView.units['1']==nil and TreeView.edges['3'].particle==stable)
-- A failed batch is retried before an explicit state refresh.
TreeView.failedDeaths={['7']=true};TreeView:Request('state')
assert(TreeView.queue[#TreeView.queue].endpoint=='state')
print('PASS: 300 deaths -> one batch; command order preserved; unchanged edges and unit positions reused; incident edge cleanup; retry ordering')
