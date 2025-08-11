// Minimal run state store for the coaching engine.
// In a real application this would be driven by sensors and user input.

export interface RunState {
  pace_now: number; // seconds per km
  pace_avg: number;
  pace_target: number;
  distance_km: number;
  split_due: boolean;
  pace_diff: number; // difference vs target in s/km
  diff_duration: number; // seconds the diff has persisted
  is_fatigue: boolean;
  elev_grad: number; // grade percentage
  hydration_due: boolean;
  in_final_km: boolean;
  ok_for_kick: boolean;
  vars: Record<string, any>; // variables for message templates
}

const state: RunState = {
  pace_now: 0,
  pace_avg: 0,
  pace_target: 0,
  distance_km: 0,
  split_due: false,
  pace_diff: 0,
  diff_duration: 0,
  is_fatigue: false,
  elev_grad: 0,
  hydration_due: false,
  in_final_km: false,
  ok_for_kick: false,
  vars: {}
};

export function getState(): RunState {
  return state;
}

export function setState(partial: Partial<RunState>) {
  Object.assign(state, partial);
}

export function resetState() {
  setState({
    pace_now: 0,
    pace_avg: 0,
    pace_target: 0,
    distance_km: 0,
    split_due: false,
    pace_diff: 0,
    diff_duration: 0,
    is_fatigue: false,
    elev_grad: 0,
    hydration_due: false,
    in_final_km: false,
    ok_for_kick: false,
    vars: {}
  });
}
