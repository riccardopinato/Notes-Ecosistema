package it.notes.ecosystem.domain

enum class FocusPhase { WORK, BREAK }
data class FocusClock(val sessionId:String,val taskId:String,val durationSeconds:Long,val deadline:Long,
    val pausedMillis:Long?=null,val phase:FocusPhase=FocusPhase.WORK,
    val workMinutes:Int=25,val shortBreakMinutes:Int=5,val longBreakMinutes:Int=15,val completedBlocks:Int=0) {
    fun remainingMillis(now:Long):Long = (pausedMillis ?: (deadline-now)).coerceIn(0,durationSeconds*1000)
    fun remaining(now:Long):Long = (remainingMillis(now)+999)/1000
    fun finished(now:Long)=remainingMillis(now)==0L
    fun pause(now:Long):FocusClock {check(pausedMillis==null && !finished(now));return copy(pausedMillis=remainingMillis(now))}
    fun resume(now:Long):FocusClock {val remaining=checkNotNull(pausedMillis);return copy(deadline=Math.addExact(now,remaining),pausedMillis=null)}
    fun next(now:Long,id:String):FocusClock {
        check(finished(now));require(id.isNotBlank())
        val count=if(phase==FocusPhase.WORK) completedBlocks+1 else completedBlocks
        val minutes=if(phase==FocusPhase.BREAK) workMinutes else if(count%4==0) longBreakMinutes else shortBreakMinutes
        return copy(sessionId=id,durationSeconds=minutes*60L,deadline=Math.addExact(now,minutes*60000L),pausedMillis=null,
            phase=if(phase==FocusPhase.WORK) FocusPhase.BREAK else FocusPhase.WORK,completedBlocks=count)
    }
    fun validate():FocusClock {
        require(sessionId.isNotBlank() && sessionId.length<=80 && taskId.isNotBlank() && taskId.length<=200)
        require(durationSeconds in 1..7200 && deadline>=0 && (pausedMillis==null || pausedMillis in 0..durationSeconds*1000))
        require(workMinutes in 1..120 && shortBreakMinutes in 1..60 && longBreakMinutes in 1..60 && completedBlocks in 0..1000000)
        return this
    }
    companion object {
        fun start(sessionId:String,taskId:String,minutes:Int,now:Long,shortBreak:Int=5,longBreak:Int=15):FocusClock {
            require(minutes in 1..120 && now>=0)
            return FocusClock(sessionId,taskId,minutes*60L,Math.addExact(now,minutes*60000L),workMinutes=minutes,
                shortBreakMinutes=shortBreak,longBreakMinutes=longBreak).validate()
        }
    }
}
