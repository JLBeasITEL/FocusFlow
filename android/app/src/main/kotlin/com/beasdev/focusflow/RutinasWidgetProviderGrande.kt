package com.beasdev.focusflow

class RutinasWidgetProviderGrande : RutinasWidgetProviderBase(
    layoutResId = R.layout.widget_rutinas_grande,
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
        FilaRutinaIds(
            R.id.widget_rutinas_fila3,
            R.id.widget_rutinas_titulo3,
            R.id.widget_rutinas_hora3,
            R.id.widget_rutinas_badge3,
            R.id.widget_rutinas_check3,
        ),
        FilaRutinaIds(
            R.id.widget_rutinas_fila4,
            R.id.widget_rutinas_titulo4,
            R.id.widget_rutinas_hora4,
            R.id.widget_rutinas_badge4,
            R.id.widget_rutinas_check4,
        ),
    ),
    progresoBarId = R.id.widget_rutinas_progreso_bar,
    dataKey = "rutinas_widget_data",
    totalParaFooterKey = "rutinas_widget_total_programadas",
)
