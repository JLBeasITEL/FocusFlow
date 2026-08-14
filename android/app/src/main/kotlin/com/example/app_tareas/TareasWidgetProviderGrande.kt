package com.example.app_tareas

class TareasWidgetProviderGrande : TareasWidgetProviderBase(
    layoutResId = R.layout.widget_tareas_grande,
    filaIds = listOf(
        FilaIds(
            R.id.widget_tareas_fila1,
            R.id.widget_tareas_titulo1,
            R.id.widget_tareas_fecha1,
            R.id.widget_tareas_prioridad1,
        ),
        FilaIds(
            R.id.widget_tareas_fila2,
            R.id.widget_tareas_titulo2,
            R.id.widget_tareas_fecha2,
            R.id.widget_tareas_prioridad2,
        ),
        FilaIds(
            R.id.widget_tareas_fila3,
            R.id.widget_tareas_titulo3,
            R.id.widget_tareas_fecha3,
            R.id.widget_tareas_prioridad3,
        ),
        FilaIds(
            R.id.widget_tareas_fila4,
            R.id.widget_tareas_titulo4,
            R.id.widget_tareas_fecha4,
            R.id.widget_tareas_prioridad4,
        ),
    ),
    abrirAppAlTocar = true,
)
