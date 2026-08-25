package com.beasdev.focusflow

class TareasWidgetProviderChico : TareasWidgetProviderBase(
    layoutResId = R.layout.widget_tareas_chico,
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
    ),
    mostrarContador = false,
    abrirAppAlTocar = true,
)
