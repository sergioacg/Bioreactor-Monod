%% Parametros del biorreactor completo - seis estados
%  Continuacion de param_biorreactor.m (clase 7).  Mismos valores de Monod,
%  mas los parametros de oxigeno, temperatura y pH.
%
%  Reactor de referencia: PILOTO de 50 L.
%
%  UNIDAD DE TIEMPO DEL MODELO: LA HORA.
%  Todo lo que entra a Simulink esta en horas.  Las potencias van en kJ/h,
%  no en W, porque mezclar W con 1/h desajusta el balance de energia por un
%  factor 3600.  Al final del archivo se imprime todo tambien en W, que es
%  como vienen las fichas tecnicas de los equipos.

clear; clc;

%% ------------------------------------------------------------------
%  1. CONSTANTES FISICAS   (no se miden: se buscan en una tabla)
%  ------------------------------------------------------------------
Kw     = 1e-14;      % [-]            producto ionico del agua, 25 C
Cstar  = 7.5;        % [mg/L]         solubilidad de O2 con aire, 30 C (Henry)
rhocp  = 4.18;       % [kJ/(L K)]     densidad por calor especifico del caldo
YQ     = 460;        % [kJ/mol O2]    calor liberado por mol de O2 respirado

%% ------------------------------------------------------------------
%  2. DEL MICROORGANISMO   (se miden en el laboratorio)
%  ------------------------------------------------------------------
umax   = 0.4;        % [1/h]          curva de crecimiento en lote
Ks     = 1.0;        % [g/L]          ajuste de la curva de Monod
Y      = 0.4;        % [gX/gS]        pendiente de X contra S consumido
Yxo    = 0.9;        % [gX/gO2]       respirometria
qA     = 2.0e-3;     % [mol/gX]       titulacion del cultivo

mumax  = umax;       % alias: los scripts de la clase 7 usan mumax

%% ------------------------------------------------------------------
%  3. DEL MEDIO DE CULTIVO   (los elige quien formula)
%  ------------------------------------------------------------------
Sin    = 10;         % [g/L]          sustrato en la alimentacion
Tin    = 22;         % [C]            temperatura del medio que entra
CT     = 0.020;      % [mol/L]        tampon fosfato total
pKa    = 6.8;        % [-]            del tampon
pH_med = 7.0;        % [-]            pH del medio fresco  (define A = 0)
Ain    = 0;          % [mol/L]        acido neto que entra, referido al medio

Ka     = 10^(-pKa);
Hmed   = 10^(-pH_med);
A0     = Hmed - Kw/Hmed - CT*Ka/(Ka + Hmed);   % [mol/L] referencia de cargas

%% ------------------------------------------------------------------
%  4. DEL EQUIPO   (se miden sobre el reactor)
%  ------------------------------------------------------------------
V      = 50;         % [L]            volumen de trabajo
Vmax   = 75;         % [L]            capacidad del vaso (tope fisico)
Tamb   = 22;         % [C]            temperatura ambiente

UA_amb_W = 7.89;     % [W/K]          ensayo de enfriamiento sin chaqueta
UA_ch_W  = 150;      % [W/K]          chaqueta
Qmax_W   = 400;      % [W]            potencia de cada actuador termico

UA_amb = UA_amb_W*3.6;   % [kJ/(h K)]  <-- lo que recibe Simulink
UA_ch  = UA_ch_W *3.6;   % [kJ/(h K)]
Qmax   = Qmax_W  *3.6;   % [kJ/h]

%% ------------------------------------------------------------------
%  5. DECISIONES DEL OPERADOR   (consignas y variables manipuladas)
%  ------------------------------------------------------------------
D      = 0.2;        % [1/h]          tasa de dilucion  -> F = D*V
Fflow  = D*V;        % [L/h]
OD_sp  = 30;         % [% sat]        consigna de oxigeno disuelto
T_sp   = 30;         % [C]            consigna de temperatura
pH_sp  = 7.0;        % [-]            consigna de pH
banda  = 5;          % [%]            banda muerta del split-range

%% ------------------------------------------------------------------
%  6. CONDICIONES INICIALES   (el estado del reactor al oprimir Run)
%  ------------------------------------------------------------------
%  El reactor arranca INOCULADO y FRIO: medio completo, poca biomasa,
%  saturado de oxigeno porque todavia nadie respira, y a temperatura
%  ambiente.  Asi los tres lazos tienen algo que hacer desde t = 0.
Vini   = V;          % [L]            lleno al volumen de trabajo
Xini   = 0.05;       % [g/L]          inoculo del 1 % aprox.
Sini   = Sin;        % [g/L]          medio fresco sin consumir
Cini   = Cstar;      % [mg/L]         saturado: aun no hay respiracion
Tini   = Tamb;       % [C]            frio, recien cargado
Aini   = 0;          % [mol/L]        por definicion, el medio fresco es A = 0

%% ------------------------------------------------------------------
%  DIMENSIONAMIENTO DEL kLa   (se elige para que la consigna sea alcanzable)
%  ------------------------------------------------------------------
mu  = @(S) umax*S./(Ks+S);

Dcrit = umax*Sin/(Ks+Sin);
assert(D < Dcrit, 'D = %.3f supera Dcrit = %.3f: el reactor se lava', D, Dcrit);

Sss = D*Ks/(umax - D);
Xss = Y*(Sin - Sss);

OUR  = mu(Sss)*Xss/Yxo;              % [g O2/(L h)]  demanda a biomasa plena
Css  = OD_sp/100*Cstar;              % [mg/L]
kLa  = OUR*1000/(Cstar - Css);       % [1/h]  el aireador necesario

kO2  = 1000/Yxo;                     % [mg O2 / g X]  factor del balance de C

%% ------------------------------------------------------------------
%  PUNTO DE OPERACION
%  ------------------------------------------------------------------
Qmet  = (OUR/32)*YQ*V;               % [kJ/h]  calor metabolico a X plena
Qperd = UA_amb*(T_sp - Tamb);        % [kJ/h]  perdida al ambiente
Qalim = rhocp*Fflow*(Tin - T_sp);    % [kJ/h]  entalpia del medio frio
Cth   = V*rhocp;                     % [kJ/K]  capacidad termica del caldo

Xcruce_lote = Xss*Qperd/Qmet;                  % [g/L] en lote (Fin = 0)
Xcruce_cont = Xss*(Qperd - Qalim)/Qmet;        % [g/L] alimentando en frio

rA       = qA*mu(Sss)*Xss;           % [mol/(L h)] produccion de acido
ubase_ss = rA;                       % [mol/(L h)] dosificacion para pH_sp

fprintf('--- Punto de operacion (V = %g L, D = %.2f 1/h, F = %.0f L/h) ---\n', V, D, Fflow);
fprintf('  Sss   = %6.2f g/L        Xss  = %6.2f g/L     Dcrit = %.3f 1/h\n', Sss, Xss, Dcrit);
fprintf('  OUR   = %6.3f g/(L h)    kLa  = %6.0f 1/h     tau_OD = %.0f s\n', OUR, kLa, 3600/kLa);
fprintf('  acido = %6.2f mmol/(L h) -> %4.0f mmol/h = %.0f mL/h de NaOH 2 M\n', ...
        rA*1000, rA*1000*V, rA*1000*V/2000*1000);

fprintf('\n--- Balance de energia en el punto de operacion ---\n');
fprintf('  metabolico       %+8.0f kJ/h  (%+5.0f W)\n', Qmet,  Qmet/3.6);
fprintf('  perdida ambiente %+8.0f kJ/h  (%+5.0f W)\n', -Qperd, -Qperd/3.6);
fprintf('  medio frio       %+8.0f kJ/h  (%+5.0f W)\n', Qalim, Qalim/3.6);
fprintf('  ------------------------------------------\n');
fprintf('  neto             %+8.0f kJ/h  (%+5.0f W)   de %4.0f kJ/h disponibles\n', ...
        Qmet - Qperd + Qalim, (Qmet - Qperd + Qalim)/3.6, Qmax);
fprintf('  cruce calentar->enfriar:  X = %.2f g/L en lote', Xcruce_lote);
if Xcruce_cont > Xss
    fprintf('   (alimentando en frio nunca cruza)\n');
else
    fprintf(',  X = %.2f g/L alimentando\n', Xcruce_cont);
end

%% ------------------------------------------------------------------
%  SEPARACION DE ESCALAS DE TIEMPO   (la razon de toda la arquitectura)
%  ------------------------------------------------------------------
tau_OD = 3600/kLa;          % [s]
tau_pH = 90;                % [s]  sonda + mezcla, valor tipico
tau_T  = Cth/UA_ch*3600;    % [s]  con la chaqueta actuando
tau_X  = 3600/mu(Sss);      % [s]

fprintf('\n--- Constantes de tiempo ---\n');
fprintf('  Oxigeno disuelto  %8.0f s\n', tau_OD);
fprintf('  pH (sonda+mezcla) %8.0f s   (tipico)\n', tau_pH);
fprintf('  Temperatura       %8.0f s = %.0f min\n', tau_T, tau_T/60);
fprintf('  Biomasa           %8.0f s = %.1f h\n', tau_X, tau_X/3600);
fprintf('  El OD es %.0f veces mas rapido que la biomasa\n', tau_X/tau_OD);