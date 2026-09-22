package it.notes.ecosystem.domain

import java.time.*
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale

enum class RepeatRule { NONE, DAILY, WEEKLY, MONTHLY }

data class TaskDetails(
    val due: String? = null,
    val priority: Int = 0,
    val repeat: RepeatRule = RepeatRule.NONE,
    val completedAt: Long? = null,
    val linkedNoteId: String? = null,
    val focusSeconds: Long = 0,
    val focusReceipts: List<String> = emptyList(),
    val completedCycles: Int = 0,
    val stage: TaskStage = TaskStage.TODO,
    val reminderAt: Long? = null,
    val reminderZone: String? = null,
    val focusHistory: List<FocusSession> = emptyList(),
    val reminderTime: String? = null,

    // Planner Pro 0.23.
    // plannedDate e due NON sono la stessa cosa.
    val plannedDate: String? = null,
    val plannedTime: String? = null,
    val plannedMinutes: Int = 30,
)

enum class PlannerScope { TODAY, UPCOMING, ALL, COMPLETED, TRASH }

enum class PlannerView {
    AGENDA,
    DAY,
    WEEK,
    MONTH,
}

data class PlannerDay(
    val date: LocalDate,
    val planned: List<Note>,
    val due: List<Note>,
) {
    val count: Int get() = planned.size
    val overdueCount: Int get() = due.count { note ->
        note.task?.due?.let(LocalDate::parse)?.isBefore(date) == true &&
            note.task.completedAt == null
    }
}

data class TimeBlock(
    val note: Note,
    val date: LocalDate,
    val start: LocalTime?,
    val minutes: Int,
) {
    val end: LocalTime?
        get() = start?.plusMinutes(minutes.toLong())
}

data class PlannerCollision(
    val firstTaskId: String,
    val secondTaskId: String,
)

data class PlannerIndex(
    val planned: Map<String, List<Note>>,
    val due: Map<String, List<Note>>,
    val unplanned: List<Note>,
)

object PlannerPro {
    const val MIN_BLOCK_MINUTES = 5
    const val MAX_BLOCK_MINUTES = 720
    const val DEFAULT_BLOCK_MINUTES = 30

    private val clock = DateTimeFormatter.ofPattern("HH:mm")

    fun parseDate(raw: String?): LocalDate? =
        raw?.let(LocalDate::parse)

    fun parseTime(raw: String?): LocalTime? =
        raw?.let { LocalTime.parse(it, clock) }

    fun formatTime(time: LocalTime): String =
        clock.format(time)

    fun plannerIndex(
        notes: List<Note>,
    ): PlannerIndex {
        val planned =
            linkedMapOf<String, MutableList<Note>>()

        val due =
            linkedMapOf<String, MutableList<Note>>()

        val unplanned =
            mutableListOf<Note>()

        notes.forEach { note ->
            val task = note.task ?: return@forEach

            if (
                note.deletedAt != null ||
                note.archived ||
                task.completedAt != null
            ) {
                return@forEach
            }

            task.plannedDate?.let { date ->
                planned.getOrPut(date) {
                    mutableListOf()
                } += note
            } ?: run {
                unplanned += note
            }

            task.due?.let { date ->
                due.getOrPut(date) {
                    mutableListOf()
                } += note
            }
        }

        val plannedSorted =
            planned.mapValues { (_, value) ->
                value.sortedWith(
                    compareBy<Note> {
                        it.task?.plannedTime ?: "99:99"
                    }.thenByDescending {
                        it.task?.priority ?: 0
                    }.thenBy {
                        it.title.lowercase(Locale.ROOT)
                    }
                )
            }

        val dueSorted =
            due.mapValues { (_, value) ->
                value.sortedByDescending {
                    it.task?.priority ?: 0
                }
            }

        return PlannerIndex(
            planned = plannedSorted,
            due = dueSorted,
            unplanned = unplanned.sortedWith(
                compareBy<Note> {
                    it.task?.due ?: "9999-12-31"
                }.thenByDescending {
                    it.task?.priority ?: 0
                }.thenBy {
                    it.title.lowercase(Locale.ROOT)
                }
            ),
        )
    }

    fun dayNotes(
        index: PlannerIndex,
        date: LocalDate,
    ): List<Note> =
        index.planned[date.toString()].orEmpty()

    fun dueOn(
        index: PlannerIndex,
        date: LocalDate,
    ): List<Note> =
        index.due[date.toString()].orEmpty()

    fun monthCount(
        index: PlannerIndex,
        date: LocalDate,
    ): Int =
        index.planned[date.toString()]?.size ?: 0

    fun dueCount(
        index: PlannerIndex,
        date: LocalDate,
    ): Int =
        index.due[date.toString()]?.size ?: 0

    fun timeBlocks(
        index: PlannerIndex,
        date: LocalDate,
    ): List<TimeBlock> =
        dayNotes(index, date).map { note ->
            val task = checkNotNull(note.task)

            TimeBlock(
                note = note,
                date = date,
                start = parseTime(task.plannedTime),
                minutes = task.plannedMinutes,
            )
        }

    fun schedule(
        task: TaskDetails,
        date: LocalDate,
        time: LocalTime? = null,
        minutes: Int = task.plannedMinutes,
    ): TaskDetails {
        require(minutes in MIN_BLOCK_MINUTES..MAX_BLOCK_MINUTES) {
            "Durata tra $MIN_BLOCK_MINUTES e $MAX_BLOCK_MINUTES minuti richiesta."
        }
        return validateTask(
            task.copy(
                plannedDate = date.toString(),
                plannedTime = time?.let(::formatTime),
                plannedMinutes = minutes,
            )
        )
    }

    fun unschedule(task: TaskDetails): TaskDetails =
        validateTask(
            task.copy(
                plannedDate = null,
                plannedTime = null,
                plannedMinutes = DEFAULT_BLOCK_MINUTES,
            )
        )

    fun moveDay(task: TaskDetails, delta: Long): TaskDetails {
        val current = parseDate(task.plannedDate)
            ?: error("L'attività non è pianificata.")
        return schedule(
            task = task,
            date = current.plusDays(delta),
            time = parseTime(task.plannedTime),
            minutes = task.plannedMinutes,
        )
    }

    fun dayNotes(
        notes: List<Note>,
        date: LocalDate,
    ): List<Note> =
        notes.asSequence()
            .filter { note ->
                note.deletedAt == null &&
                    !note.archived &&
                    note.task?.completedAt == null &&
                    note.task?.plannedDate == date.toString()
            }
            .sortedWith(
                compareBy<Note> {
                    it.task?.plannedTime ?: "99:99"
                }.thenByDescending {
                    it.task?.priority ?: 0
                }.thenBy {
                    it.title.lowercase(Locale.ROOT)
                }
            )
            .toList()

    fun unplanned(
        notes: List<Note>,
    ): List<Note> =
        notes.asSequence()
            .filter {
                it.deletedAt == null &&
                    !it.archived &&
                    it.task != null &&
                    it.task.completedAt == null &&
                    it.task.plannedDate == null
            }
            .sortedWith(
                compareBy<Note> {
                    it.task?.due ?: "9999-12-31"
                }.thenByDescending {
                    it.task?.priority ?: 0
                }.thenBy {
                    it.title.lowercase(Locale.ROOT)
                }
            )
            .toList()

    fun dueOn(
        notes: List<Note>,
        date: LocalDate,
    ): List<Note> =
        notes.asSequence()
            .filter {
                it.deletedAt == null &&
                    !it.archived &&
                    it.task?.completedAt == null &&
                    it.task?.due == date.toString()
            }
            .sortedByDescending {
                it.task?.priority ?: 0
            }
            .toList()

    fun timeBlocks(
        notes: List<Note>,
        date: LocalDate,
    ): List<TimeBlock> =
        dayNotes(notes, date).map { note ->
            val task = checkNotNull(note.task)
            TimeBlock(
                note = note,
                date = date,
                start = parseTime(task.plannedTime),
                minutes = task.plannedMinutes,
            )
        }

    fun collisions(blocks: List<TimeBlock>): List<PlannerCollision> {
        val timed = blocks.filter { it.start != null }
        val collisions = mutableListOf<PlannerCollision>()

        for (i in timed.indices) {
            val a = timed[i]
            val aStart = checkNotNull(a.start)
            val aEnd = checkNotNull(a.end)

            for (j in i + 1 until timed.size) {
                val b = timed[j]
                val bStart = checkNotNull(b.start)
                val bEnd = checkNotNull(b.end)

                if (aStart < bEnd && bStart < aEnd) {
                    collisions += PlannerCollision(
                        firstTaskId = a.note.id,
                        secondTaskId = b.note.id,
                    )
                }
            }
        }

        return collisions
    }

    fun weekStart(date: LocalDate): LocalDate =
        date.with(java.time.temporal.TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))

    fun weekDays(date: LocalDate): List<LocalDate> {
        val start = weekStart(date)
        return (0L..6L).map(start::plusDays)
    }

    /**
     * 6 settimane x 7 giorni.
     * Questo evita salti di altezza fra i mesi.
     */
    fun monthGrid(month: YearMonth): List<LocalDate> {
        val first = month.atDay(1)
        val gridStart = first.with(
            java.time.temporal.TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)
        )
        return (0L until 42L).map(gridStart::plusDays)
    }

    fun monthCount(
        notes: List<Note>,
        date: LocalDate,
    ): Int =
        notes.count {
            it.deletedAt == null &&
                !it.archived &&
                it.task?.completedAt == null &&
                it.task?.plannedDate == date.toString()
        }

    fun dueCount(
        notes: List<Note>,
        date: LocalDate,
    ): Int =
        notes.count {
            it.deletedAt == null &&
                !it.archived &&
                it.task?.completedAt == null &&
                it.task?.due == date.toString()
        }

    fun dayLabel(date: LocalDate, locale: Locale = Locale.getDefault()): String {
        val day = date.dayOfWeek.getDisplayName(TextStyle.SHORT, locale)
        return "$day ${date.dayOfMonth}"
    }

    fun monthLabel(month: YearMonth, locale: Locale = Locale.getDefault()): String =
        month.month.getDisplayName(TextStyle.FULL, locale)
            .replaceFirstChar { if (it.isLowerCase()) it.titlecase(locale) else it.toString() } +
            " ${month.year}"
}

fun validateTask(task: TaskDetails): TaskDetails {
    require(task.priority in 0..3) { "Priorità non valida." }

    task.due?.let {
        require(LocalDate.parse(it).year in 2000..2200) {
            "Data tra 2000 e 2200 richiesta."
        }
    }

    require(task.repeat == RepeatRule.NONE || task.due != null) {
        "La ricorrenza richiede una data."
    }

    require(task.completedAt == null || task.completedAt >= 0)

    require(
        task.linkedNoteId == null ||
            task.linkedNoteId.isNotBlank() &&
            task.linkedNoteId.length <= 200
    )

    require(task.focusSeconds in 0..86400000)
    require(task.completedCycles in 0..1000000)

    require(
        task.focusReceipts.size <= 200 &&
            task.focusReceipts.distinct().size == task.focusReceipts.size
    )
    require(task.focusReceipts.all { it.length in 1..80 })

    require((task.reminderAt == null) == (task.reminderZone == null)) {
        "Promemoria incompleto."
    }

    task.reminderTime?.let {
        require(task.reminderAt != null)
        require(Regex("[0-2][0-9]:[0-5][0-9]").matches(it))
        LocalTime.parse(it)
    }

    task.reminderAt?.let {
        require(it in 946684800000L..7258118399999L)
        ZoneId.of(task.reminderZone)
    }

    require(
        task.focusHistory.size <= 200 &&
            task.focusHistory.map { it.id }.distinct().size == task.focusHistory.size
    )
    require(
        task.focusHistory.all {
            it.id in task.focusReceipts &&
                it.seconds in 1..7200 &&
                it.endedAt in 0..7258118399999L
        }
    )
    require(task.focusHistory.sumOf { it.seconds } <= task.focusSeconds)

    // Planner Pro.
    task.plannedDate?.let {
        require(LocalDate.parse(it).year in 2000..2200) {
            "Data di pianificazione tra 2000 e 2200 richiesta."
        }
    }

    require(task.plannedTime == null || task.plannedDate != null) {
        "Un orario pianificato richiede anche il giorno."
    }

    task.plannedTime?.let {
        require(Regex("[0-2][0-9]:[0-5][0-9]").matches(it)) {
            "Orario non valido."
        }
        LocalTime.parse(it)
    }

    require(
        task.plannedMinutes in
            PlannerPro.MIN_BLOCK_MINUTES..PlannerPro.MAX_BLOCK_MINUTES
    ) {
        "Durata del blocco non valida."
    }

    return task
}

fun completePlannedTask(
    task: TaskDetails,
    completed: Boolean,
    now: Long,
    today: LocalDate,
): TaskDetails {
    validateTask(task)
    require(now >= 0)

    if (!completed) {
        return validateTask(
            task.copy(completedAt = null)
        )
    }

    if (task.completedAt != null) {
        return validateTask(
            task.copy(
                reminderAt = null,
                reminderZone = null,
                reminderTime = null,
            )
        )
    }

    if (task.repeat == RepeatRule.NONE) {
        return validateTask(
            task.copy(
                completedAt = now,
                reminderAt = null,
                reminderZone = null,
                reminderTime = null,
            )
        )
    }

    var next = LocalDate.parse(task.due)

    do {
        next = when (task.repeat) {
            RepeatRule.DAILY -> next.plusDays(1)
            RepeatRule.WEEKLY -> next.plusWeeks(1)
            RepeatRule.MONTHLY -> next.plusMonths(1)
            RepeatRule.NONE -> error("Ricorrenza non valida.")
        }
    } while (!next.isAfter(today))

    val nextReminder = task.reminderAt?.let { old ->
        val zone = ZoneId.of(task.reminderZone)
        val time =
            task.reminderTime?.let(LocalTime::parse)
                ?: Instant.ofEpochMilli(old)
                    .atZone(zone)
                    .toLocalTime()

        next.atTime(time)
            .atZone(zone)
            .toInstant()
            .toEpochMilli()
    }

    /*
     * La scadenza ricorrente avanza.
     * Il time block della precedente occorrenza viene invece liberato:
     * l'utente decide quando pianificare il nuovo ciclo.
     */
    return validateTask(
        task.copy(
            due = next.toString(),
            completedCycles = task.completedCycles + 1,
            stage = TaskStage.TODO,
            reminderAt = nextReminder,
            plannedDate = null,
            plannedTime = null,
            plannedMinutes = PlannerPro.DEFAULT_BLOCK_MINUTES,
        )
    )
}

fun recordFocus(
    task: TaskDetails,
    sessionId: String,
    seconds: Long,
): TaskDetails {
    validateTask(task)
    require(seconds in 1..7200)

    if (sessionId in task.focusReceipts) return task

    require(task.focusReceipts.size < 200) {
        "Limite di 200 sessioni per attività raggiunto."
    }

    return validateTask(
        task.copy(
            focusSeconds = task.focusSeconds + seconds,
            focusReceipts = task.focusReceipts + sessionId,
        )
    )
}

fun plannerNotes(
    notes: List<Note>,
    scope: PlannerScope,
    today: LocalDate,
    query: String = "",
): List<Note> =
    notes.filter { n ->
        val t = n.task ?: return@filter false
        val date = t.due?.let(LocalDate::parse)

        val visible =
            if (scope == PlannerScope.TRASH) {
                n.deletedAt != null
            } else {
                n.deletedAt == null && !n.archived
            }

        visible &&
            (
                query.isBlank() ||
                    n.title.contains(query.trim(), true) ||
                    n.body.contains(query.trim(), true) ||
                    n.tags.any { it.contains(query.trim(), true) }
            ) &&
            when (scope) {
                PlannerScope.TODAY ->
                    t.completedAt == null &&
                        date != null &&
                        !date.isAfter(today)

                PlannerScope.UPCOMING ->
                    t.completedAt == null &&
                        date != null &&
                        date.isAfter(today)

                PlannerScope.ALL ->
                    t.completedAt == null

                PlannerScope.COMPLETED ->
                    t.completedAt != null

                PlannerScope.TRASH ->
                    true
            }
    }.sortedWith(
        compareBy<Note> {
            it.task!!.due ?: "9999-12-31"
        }.thenByDescending {
            it.task!!.priority
        }.thenBy {
            it.id
        }
    )
