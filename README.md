# Biorreactor de Monod — modelo no lineal en Simulink

Modelo dinámico de un biorreactor de tanque agitado, con **seis estados** y las seis entradas que manipula un fermentador real. Pensado para servir de planta: se conecta a los controladores que quieras y se simula.

![Respuesta en lazo abierto](docs/lazo_abierto_biorreactor.png)

La mayoría de los modelos de quimiostato que circulan tienen dos estados, biomasa y sustrato, y asumen que el volumen, el oxígeno, la temperatura y el pH están perfectamente controlados. Eso sirve para estudiar el lavado, pero no para diseñar los lazos — porque los lazos son justamente lo que se asumió. Este modelo devuelve esas cuatro hipótesis.

Sirve como planta para probar PID, cascada, feedforward, antiwindup, transferencia sin golpe, split-range y control multivariable, y como ejemplo de dos problemas que no suelen estar en los modelos de juguete: una variable con **dos actuadores opuestos** (calentar / enfriar) y una salida que es una **ecuación algebraica implícita** del estado (el pH).

Requiere MATLAB con Simulink. Sin toolboxes adicionales.

---

## El modelo

Seis balances. Todos comparten la misma unidad de tiempo: **la hora**.

$$\frac{dV}{dt} = F_{in} - F_{out}$$

$$\frac{dX}{dt} = (\mu - D)\,X$$

$$\frac{dS}{dt} = D\,(S_{in} - S) - \frac{\mu}{Y}X$$

$$\frac{dC}{dt} = k_La\,(C^* - C) - 1000\,\frac{\mu}{Y_{XO}}X$$

$$\frac{dT}{dt} = \frac{q_{met}V - UA_{amb}(T - T_{amb}) + Q_{cal} - Q_{enf}}{V\rho c_p}$$

$$\frac{dA}{dt} = D\,(A_{in} - A) + q_A\,\mu X - u_{base}$$

con

$$\mu = \frac{\mu_{max}S}{K_s + S} \qquad D = \frac{F_{in}}{V} \qquad q_{met} = \frac{Y_Q}{32}\frac{\mu X}{Y_{XO}}$$

| estado | unidad | | entrada | unidad |
|---|---|---|---|---|
| V volumen de caldo | L | | `Sin` sustrato en la alimentación | g/L |
| X biomasa | g/L | | `Fin` caudal de entrada | L/h |
| S sustrato limitante | g/L | | `Fout` caudal de salida | L/h |
| C oxígeno disuelto | mg/L | | `Qcal` potencia de calentamiento | kJ/h |
| T temperatura | °C | | `Qenf` potencia de enfriamiento | kJ/h |
| A ácido neto acumulado | mol/L | | `u_base` dosificación de base | mol/(L·h) |

Salidas: `X`, `S`, `pH`, `V`, `C`, `T`.

El bloque es **autocontenido**: los 24 parámetros viven en su máscara, repartidos en cuatro pestañas, con valores numéricos. No hace falta cargar nada en el workspace para simularlo.

---

## Las dos trampas de unidades

Si vas a modificar el modelo, lee esto antes que nada. Los dos errores más caros del proyecto no estuvieron en las ecuaciones sino en las unidades, y ninguno de los dos produce un mensaje de error.

**El factor 1000 del balance de oxígeno.** C se mide en mg/L porque es lo que marca la sonda; X se reporta en g/L. Al restar los dos términos hay que traducir. Sin ese factor el consumo entra mil veces más pequeño y **el oxígeno disuelto se queda clavado en 100 % para siempre**: el modelo simula perfecto y la respuesta es falsa.

**El factor 3600 del balance de energía.** Las fichas técnicas de la resistencia y del chiller dan vatios, pero μmax está en 1/h. Aquí todas las potencias térmicas van en **kJ/h**, y `param_biorreactor_completo.m` guarda las dos versiones de cada parámetro: `UA_amb_W = 7.89` es la ficha del equipo, `UA_amb = 28.4` es lo que recibe Simulink.

La forma de cazarlos no es revisar el diagrama: es evaluar cada término de cada balance en el punto de operación, con calculadora, y comprobar que los que deben cancelarse se cancelen. Si dos términos que deberían ser iguales difieren en un factor redondo —1000, 3600, 60— son unidades. Si difieren en un factor feo, ahí sí revisa el modelo.

---

## Cómo correrlo

```matlab
param_biorreactor_completo      % imprime el punto de operación, opcional
open bioreactor_monod_completo.slx
```

Para la corrida en lazo abierto de la figura, las seis entradas son constantes:

| `Sin` | `Fin` | `Fout` | `Qcal` | `Qenf` | `u_base` |
|---|---|---|---|---|---|
| 10 | 10 | 10 | 0 | 0 | 0 |

Solver `ode15s`, RelTol `1e-6`, StopTime 80 h. El `ode45` también funciona, pero el modo de 24 segundos del oxígeno le fija el paso durante las 80 horas completas.

### Verificación

Si el modelo está intacto, esa corrida da exactamente esto:

| t [h] | X | S | OD % | T | pH |
|---|---|---|---|---|---|
| 0 | 0.010 | 10.00 | 100 | 22.0 | 7.00 |
| 20 | 0.260 | 9.35 | 91 | 23.2 | 6.95 |
| 30 | 1.255 | 6.86 | 58 | 27.9 | 6.78 |
| 40 | 3.516 | 1.21 | 25 | 39.4 | 6.35 |
| 80 | 3.600 | 1.00 | 30 | 42.2 | 6.33 |

X y S llegan solos al punto de diseño: la biología se autorregula. T y pH no, y no derivan — se estabilizan en un equilibrio nuevo, equivocado y perfectamente estable. Esa es la diferencia entre una variable que el proceso regula y una que necesita un lazo.

Si el OD se queda en 100 %, falta el factor 1000. Si X se va a cero, revisa `Sin`.

---

## Punto de operación de referencia

Piloto de 50 L con D = 0.2 h⁻¹ (F = 10 L/h) y Sin = 10 g/L:

| magnitud | valor |
|---|---|
| S, X en régimen | 1.00 y 3.60 g/L |
| D crítico (lavado) | 0.364 h⁻¹ |
| demanda de oxígeno | 0.80 g O₂/(L·h) |
| kLa para 30 % de saturación | 152 h⁻¹ |
| calor metabólico | 575 kJ/h (160 W) |
| producción de ácido | 1.44 mmol/(L·h) ≈ 36 mL/h de NaOH 2 M |

Separación de escalas de tiempo, que es lo que permite diseñar cada lazo por separado:

| oxígeno disuelto | pH | temperatura | biomasa |
|---|---|---|---|
| 24 s | ~90 s | ~23 min | 5 h |

---

## El pH, que es el único punto no trivial

El balance de cargas da A en función de [H⁺] de forma explícita,

$$A = [H^+] - \frac{K_w}{[H^+]} - \frac{C_T K_a}{K_a + [H^+]}$$

pero el modelo necesita el camino contrario: dado A, hallar [H⁺]. Esa inversión es una cúbica y no tiene fórmula cerrada.

`ph_fcn.m` usa **bisección con un número fijo de 40 iteraciones**, no `fzero`. Dos razones: el bloque siempre tarda lo mismo, lo que importa si vas a generar código o simular en tiempo real, y el generador de código lo acepta. La bisección no puede fallar porque la función de cargas es monótona decreciente en pH, así que hay una solución y solo una. El error medido es de 6×10⁻¹² unidades de pH.

En el diagrama, la EDO y la ecuación algebraica van **en serie**, no en un lazo:

```
balance de ácido  →  ∫  →  A  →  [ ph_fcn ]  →  pH
```

No hay lazo algebraico porque el pH nunca vuelve a entrar al balance. `tools/ph_lookup_biorreactor.m` genera una tabla equivalente por si prefieres un Lookup Table; el error de interpolación con 161 puntos es de 0.0007 unidades de pH.

---

## Qué no hace el modelo

Tenlo presente antes de sacar conclusiones:

- **μ depende solo del sustrato.** Ni el oxígeno ni la temperatura ni el pH limitan el crecimiento, así que en lazo abierto el cultivo "sobrevive" a 42 °C y a OD cero. Añadir doble limitación es un factor más en μ: $\frac{C}{K_O+C}$, con K_O del orden de 0.1–0.3 mg/L.
- **El balance de energía no incluye la entalpía del medio que entra**, $\rho c_p F_{in}(T_{in}-T)$. En lote vale cero; alimentando a D = 0.2 con medio a 22 °C pesa −334 kJ/h, más que la pérdida al ambiente. Es además la perturbación medible ideal para probar feedforward.
- **Se desprecia el arrastre de oxígeno por el efluente**, −D·C: es mil veces menor que la transferencia.
- **No hay dinámica de sensores ni de actuadores.** Las sondas reales de OD y pH tienen retardos de decenas de segundos, y son las que vuelven inestable el lazo.

Las dos últimas son las que conviene añadir primero si quieres un banco de pruebas realista.

---

## Archivos

| archivo | qué es |
|---|---|
| `bioreactor_monod_completo.slx` | el modelo |
| `param_biorreactor_completo.m` | parámetros por origen, punto de operación y escalas de tiempo |
| `ph_fcn.m` | cuerpo del bloque MATLAB Function que convierte A en pH |
| `splitrange_fcn.m` | cuerpo del bloque MATLAB Function del split-range |
| `tools/` | scripts que reconstruyen la máscara y generan la tabla de pH; no hacen falta para simular |
| `docs/` | la figura de referencia y el script que la genera |

`ph_fcn.m` y `splitrange_fcn.m` son copias de referencia: el código que corre vive dentro del `.slx`. Si editas uno, edita el otro.

---

## Licencia

Código bajo licencia MIT. Documentación y figuras bajo CC BY 4.0.

## Cómo citar

> Castaño Giraldo, S. A. (2026). *Biorreactor de Monod — modelo no lineal en Simulink.*

Desarrollado para el curso de Control de Bioprocesos de la Universidad EIA (Medellín, Colombia).
