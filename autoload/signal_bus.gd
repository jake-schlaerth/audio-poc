extends Node
## Global signal bus, registered as the autoload "SignalBus".
##
## A home for cross-cutting signals so emitters and listeners never need a
## reference to each other: one side calls [code]SignalBus.some_signal.emit(...)[/code],
## any number of other scripts call [code]SignalBus.some_signal.connect(...)[/code].
##
## Keep this file to signal declarations only — no state, no game logic. Group
## related signals and document the payload of each.

## The title phrase changed to [param phrase] (its [param index] in the phrase
## list). Emitted by [TextCycler] after each successful cycle.
signal phrase_changed(phrase: String, index: int)

## Something asked for a spark halo hugging [param normalized_rect] (normalized
## screen coordinates, Y-down). [FluidSim] listens and fires the volley.
signal fluid_sparks_requested(normalized_rect: Rect2)

## The smoothed fluid stir level changed; [param activity] is 0..1. [FluidAudio]
## listens and crossfades the music — connect here instead of polling [FluidSim].
signal fluid_activity_changed(activity: float)
