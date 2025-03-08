import discord
from discord.ext import commands, tasks
from datetime import datetime, timedelta
import asyncio

intents = discord.Intents.default()
intents.members = True
intents.message_content = True

bot = commands.Bot(command_prefix='!', intents=intents)

# 防御系统配置
ANTI_RAID_CONFIG = {
    "MAX_MESSAGES": 7,  # 5秒内允许的最大消息数
    "TIME_WINDOW": 5,   # 时间窗口(秒)
    "NEW_ACCOUNT_DAYS": 3,  # 判定为新账号的天数
    "AUTO_BAN_THRESHOLD": 3  # 自动封禁的违规次数
}

# 用户活动跟踪字典
user_activity = {}

# 自动清理任务
@tasks.loop(minutes=30)
async def auto_clean():
    now = datetime.now()
    # 清理超过1小时不活跃的用户数据
    inactive_users = [user_id for user_id, data in user_activity.items() 
                     if (now - data['last_update']).total_seconds() > 3600]
    for user_id in inactive_users:
        del user_activity[user_id]

# 高级消息过滤
async def check_message_threat(message):
    # 检测刷屏行为
    user_id = message.author.id
    now = datetime.now()
    
    if user_id not in user_activity:
        user_activity[user_id] = {
            'count': 0,
            'timestamps': [],
            'last_update': now
        }
    
    # 更新时间窗口
    user_activity[user_id]['timestamps'] = [
        t for t in user_activity[user_id]['timestamps']
        if (now - t).total_seconds() <= ANTI_RAID_CONFIG['TIME_WINDOW']
    ]
    
    # 检查消息频率
    user_activity[user_id]['timestamps'].append(now)
    user_activity[user_id]['count'] = len(user_activity[user_id]['timestamps'])
    
    if user_activity[user_id]['count'] >= ANTI_RAID_CONFIG['MAX_MESSAGES']:
        await punish_user(message.author, reason="消息刷屏")
        return True
    
    # 检测新账号
    account_age = (now - message.author.created_at).days
    if account_age < ANTI_RAID_CONFIG['NEW_ACCOUNT_DAYS']:
        await message.channel.send(
            f"{message.author.mention} 新账号需要验证，请联系管理员",
            delete_after=10
        )
        await message.delete()
        return True
    
    return False

# 惩罚系统
async def punish_user(user, reason):
    try:
        # 自动时效禁言
        await user.timeout(timedelta(minutes=30), reason=f"安全系统自动处理: {reason}")
        # 记录违规次数
        if user.id not in user_activity:
            user_activity[user.id] = {'violations': 0}
        user_activity[user.id]['violations'] += 1
        
        # 达到封禁阈值
        if user_activity[user.id]['violations'] >= ANTI_RAID_CONFIG['AUTO_BAN_THRESHOLD']:
            await user.ban(reason="多次违反安全规则")
    except discord.Forbidden:
        print(f"权限不足，无法惩罚 {user.name}")

# 消息处理
@bot.event
async def on_message(message):
    if message.author.bot:
        return
    
    # 执行安全检测
    if await check_message_threat(message):
        return
    
    await bot.process_commands(message)

# 增强版清理命令
@bot.command()
@commands.has_permissions(manage_messages=True)
async def purge(ctx, amount: int = 10):
    """批量清理消息(管理专用)"""
    if amount > 100:
        await ctx.send("单次最多清理100条消息", delete_after=5)
        return
    
    deleted = await ctx.channel.purge(limit=amount + 1)
    msg = await ctx.send(f"已清理 {len(deleted)-1} 条消息", delete_after=5)

# 安全验证命令
@bot.command()
@commands.has_permissions(administrator=True)
async def verify(ctx, user: discord.Member):
    """管理员验证用户"""
    await user.timeout(None)
    await ctx.send(f"{user.mention} 已通过验证")

# 启动时初始化
@bot.event
async def on_ready():
    auto_clean.start()
    print(f'安全机器人 {bot.user} 已启动')

bot.run('YOUR_BOT_TOKEN')
