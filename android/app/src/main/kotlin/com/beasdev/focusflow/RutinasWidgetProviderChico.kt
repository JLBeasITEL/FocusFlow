package com.beasdev.focusflow

class RutinasWidgetProviderChico : RutinasWidgetProviderBase(
    layoutResId = R.layout.widget_rutinas_chico,
    filaIds = listOf(
        FilaRutinaIds(
            R.id.widget_rutinas_fila1,
            R.id.widget_rutinas_titulo1,
            R.id.widget_rutinas_hora1,
            R.id.widget_rutinas_badge1,
            R.id.widget_rutinas_check1,
        ),
        FilaRutinaIds(
            R.id.widget_rutinas_fila2,
            R.id.widget_rutinas_titulo2,
            R.id.widget_rutinas_hora2,
            R.id.widget_rutinas_badge2,
            R.id.widget_rutinas_check2,
        ),
    ),
    progresoBarId = null,
    dataKey = "rutinas_widget_data_chico",
    totalParaFooterKey = "rutinas_widget_total_programadas",
    mostrarBadgeHecha = false,
)
