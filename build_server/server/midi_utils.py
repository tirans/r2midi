import asyncio
import logging
import logging.config
from typing import Dict, List, Optional, Tuple

# Get logger
logger = logging.getLogger(__name__)

# Initialize python-rtmidi
try:
    import rtmidi
    logger.info("Successfully imported python-rtmidi module")
except ImportError:
    logger.error("Failed to import python-rtmidi module")
    rtmidi = None


class MidiUtils:
    """Utilities for MIDI port detection and command execution"""

    @staticmethod
    def get_midi_ports() -> Dict[str, List[str]]:
        """
        Get all available MIDI ports on the system
        Returns a dictionary with 'in' and 'out' keys containing lists of port names
        """
        logger.info("Getting MIDI ports...")

        # Check if rtmidi is available
        if rtmidi is None:
            logger.error("rtmidi module is not available")
            return {"in": [], "out": []}

        try:
            # Try to create MIDI input and output objects using python-rtmidi API
            try:
                midi_in = rtmidi.MidiIn()
                midi_out = rtmidi.MidiOut()
            except AttributeError:
                logger.error("rtmidi module does not have MidiIn or MidiOut attributes")
                return {"in": [], "out": []}

            # Get port names using python-rtmidi API
            in_ports = [midi_in.get_port_name(i) for i in range(midi_in.get_port_count())]
            out_ports = [midi_out.get_port_name(i) for i in range(midi_out.get_port_count())]

            logger.info(
                f"Found {len(in_ports)} MIDI in ports and {len(out_ports)} MIDI out ports"
            )
            logger.debug(f"MIDI in ports: {in_ports}")
            logger.debug(f"MIDI out ports: {out_ports}")

            return {"in": in_ports, "out": out_ports}
        except Exception as e:
            logger.error(f"Error getting MIDI ports: {str(e)}")
            # Return empty lists as fallback
            return {"in": [], "out": []}

    @staticmethod
    def send_midi_command(
        command: str, sequencer_port: Optional[str] = None
    ) -> Tuple[bool, str]:
        """
        Execute MIDI command using python-rtmidi and optionally send to sequencer port

        Args:
            command: The MIDI command to execute (in legacy sendmidi format for backward compatibility)
            sequencer_port: Optional sequencer port to send the command to

        Returns:
            Tuple of (success, message)
        """
        logger.info(f"Executing MIDI command: {command}")
        try:
            # Parse the command string to extract port name, channel, cc_0, and pgm values
            # Expected format: legacy sendmidi format: dev "Port Name" ch <channel> cc 0 <cc_0> pc <pgm>

            # Extract port name
            dev_pos = command.find('dev "')
            if dev_pos < 0:
                dev_pos = command.find("dev '")
                if dev_pos < 0:
                    return False, "Invalid command format: missing 'dev' parameter"
                quote_char = "'"
            else:
                quote_char = '"'

            port_start_pos = dev_pos + 5  # Position after 'dev "'
            port_end_pos = command.find(quote_char, port_start_pos)
            if port_end_pos < 0:
                return (
                    False,
                    "Invalid command format: missing closing quote for port name",
                )

            port_name = command[port_start_pos:port_end_pos]

            # Extract channel
            ch_pos = command.find("ch ", port_end_pos)
            if ch_pos < 0:
                return False, "Invalid command format: missing 'ch' parameter"

            ch_start_pos = ch_pos + 3  # Position after 'ch '
            ch_end_pos = command.find(" ", ch_start_pos)
            if ch_end_pos < 0:
                ch_end_pos = len(command)

            try:
                channel = int(command[ch_start_pos:ch_end_pos])
                if channel < 1 or channel > 16:
                    return (
                        False,
                        f"Invalid MIDI channel: {channel}. Must be between 1 and 16.",
                    )
            except ValueError:
                return (
                    False,
                    f"Invalid MIDI channel: {command[ch_start_pos:ch_end_pos]}",
                )

            # Extract cc_0 value
            cc_pos = command.find("cc 0 ", ch_end_pos)
            if cc_pos < 0:
                return False, "Invalid command format: missing 'cc 0' parameter"

            cc_start_pos = cc_pos + 5  # Position after 'cc 0 '
            cc_end_pos = command.find(" ", cc_start_pos)
            if cc_end_pos < 0:
                cc_end_pos = len(command)

            try:
                cc_0_value = int(command[cc_start_pos:cc_end_pos])
                if cc_0_value < 0 or cc_0_value > 127:
                    return (
                        False,
                        f"Invalid CC value: {cc_0_value}. Must be between 0 and 127.",
                    )
            except ValueError:
                return False, f"Invalid CC value: {command[cc_start_pos:cc_end_pos]}"

            # Extract pgm value
            pc_pos = command.find("pc ", cc_end_pos)
            if pc_pos < 0:
                return False, "Invalid command format: missing 'pc' parameter"

            pc_start_pos = pc_pos + 3  # Position after 'pc '
            pc_end_pos = command.find(" ", pc_start_pos)
            if pc_end_pos < 0:
                pc_end_pos = len(command)

            try:
                pgm_value = int(command[pc_start_pos:pc_end_pos])
                if pgm_value < 0 or pgm_value > 127:
                    return (
                        False,
                        f"Invalid program change value: {pgm_value}. Must be between 0 and 127.",
                    )
            except ValueError:
                return (
                    False,
                    f"Invalid program change value: {command[pc_start_pos:pc_end_pos]}",
                )

            # Send MIDI messages using rtmidi
            success, message = MidiUtils._send_rtmidi_message(
                port_name, channel, cc_0_value, pgm_value
            )
            if not success:
                return False, message

            # If sequencer port is specified, send to that port as well
            if sequencer_port:
                logger.info(f"Sending to sequencer port: {sequencer_port}")
                try:
                    seq_success, seq_message = MidiUtils._send_rtmidi_message(
                        sequencer_port, channel, cc_0_value, pgm_value
                    )
                    if not seq_success:
                        logger.error(f"Error sending to sequencer port: {seq_message}")
                        return False, f"Error sending to sequencer port: {seq_message}"
                    else:
                        logger.info(
                            f"Successfully sent to sequencer port: {sequencer_port}"
                        )
                except Exception as e:
                    logger.error(f"Error sending to sequencer port: {str(e)}")
                    # Continue execution even if sequencer command fails
                    # Just log the error but don't fail the whole operation

            logger.info("MIDI command executed successfully")
            return True, "Command executed successfully"

        except Exception as e:
            logger.error(f"Unexpected error executing MIDI command: {str(e)}")
            return False, f"Unexpected error: {str(e)}"

    @staticmethod
    def _send_rtmidi_message(
        port_name: str, channel: int, cc_0_value: int, pgm_value: int
    ) -> Tuple[bool, str]:
        """
        Send MIDI messages using python-rtmidi

        Args:
            port_name: MIDI output port name
            channel: MIDI channel (1-16)
            cc_0_value: Value for CC 0 (Bank Select)
            pgm_value: Value for Program Change

        Returns:
            Tuple of (success, message)
        """
        # Check if rtmidi is available
        if rtmidi is None:
            logger.error("rtmidi module is not available")
            return False, "rtmidi module is not available"

        try:
            # Try to create MIDI output object using python-rtmidi API
            try:
                midi_out = rtmidi.MidiOut()
            except AttributeError:
                logger.error("rtmidi module does not have MidiOut attribute")
                return False, "rtmidi module does not have MidiOut attribute"

            # Get available output ports using python-rtmidi API
            available_ports = [midi_out.get_port_name(i) for i in range(midi_out.get_port_count())]

            # Find the port index
            port_index = None
            logger.debug(
                f"Looking for port '{port_name}' in available ports: {available_ports}"
            )
            for i, port in enumerate(available_ports):
                if port_name in port:
                    port_index = i
                    logger.debug(f"Found port '{port_name}' at index {i}")
                    break

            if port_index is None:
                logger.warning(
                    f"MIDI output port '{port_name}' not found in available ports"
                )
                return False, f"MIDI output port '{port_name}' not found"

            # Open the port
            midi_out.open_port(port_index)

            # Send Bank Select (CC 0) message using raw MIDI bytes
            # MIDI CC message: [0xB0 + channel-1, controller, value]
            cc_message = [0xB0 + (channel - 1), 0, cc_0_value]
            midi_out.send_message(cc_message)
            logger.debug(f"Sent CC message: {cc_message}")

            # Send Program Change message using raw MIDI bytes
            # MIDI PC message: [0xC0 + channel-1, program]
            pc_message = [0xC0 + (channel - 1), pgm_value]
            midi_out.send_message(pc_message)
            logger.debug(f"Sent PC message: {pc_message}")

            # Close the port
            midi_out.close_port()

            return True, "MIDI messages sent successfully"

        except Exception as e:
            logger.error(f"Error sending MIDI messages with rtmidi: {str(e)}")
            return False, f"Error sending MIDI messages: {str(e)}"

    @staticmethod
    def send_preset_select(
        port_name: str,
        channel: int,
        pgm_value: int,
        cc_value: int = 0,
        cc_number: int = 0,
    ) -> Tuple[bool, str]:
        """
        Send preset selection MIDI messages using python-rtmidi

        Args:
            port_name: MIDI output port name
            channel: MIDI channel (1-16)
            pgm_value: Value for Program Change (0-127)
            cc_value: Value for CC (0-127), defaults to 0
            cc_number: CC number (0-127), defaults to 0 (Bank Select)

        Returns:
            Tuple of (success, message)
        """
        logger.info(
            f"Sending preset select: port={port_name}, channel={channel}, cc{cc_number}={cc_value}, pgm={pgm_value}"
        )

        # Check if rtmidi is available
        if rtmidi is None:
            logger.error("rtmidi module is not available")
            return False, "rtmidi module is not available"

        try:
            # Try to create MIDI output object using python-rtmidi API
            try:
                midi_out = rtmidi.MidiOut()
            except AttributeError:
                logger.error("rtmidi module does not have MidiOut attribute")
                return False, "rtmidi module does not have MidiOut attribute"

            # Get available output ports using python-rtmidi API
            available_ports = [midi_out.get_port_name(i) for i in range(midi_out.get_port_count())]

            # Find the port index
            port_index = None
            logger.debug(
                f"Looking for port '{port_name}' in available ports: {available_ports}"
            )
            for i, port in enumerate(available_ports):
                if port_name in port:
                    port_index = i
                    logger.debug(f"Found port '{port_name}' at index {i}")
                    break

            if port_index is None:
                logger.warning(
                    f"MIDI output port '{port_name}' not found in available ports"
                )
                return False, f"MIDI output port '{port_name}' not found"

            # Open the port
            midi_out.open_port(port_index)

            # Send CC message using raw MIDI bytes
            # MIDI CC message: [0xB0 + channel-1, controller, value]
            cc_message = [0xB0 + (channel - 1), cc_number, cc_value]
            midi_out.send_message(cc_message)
            logger.debug(f"Sent CC message: {cc_message}")

            # Send Program Change message using raw MIDI bytes
            # MIDI PC message: [0xC0 + channel-1, program]
            pc_message = [0xC0 + (channel - 1), pgm_value]
            midi_out.send_message(pc_message)
            logger.debug(f"Sent PC message: {pc_message}")

            # Close the port
            midi_out.close_port()

            return True, "Preset selection sent successfully"

        except Exception as e:
            logger.error(f"Error sending preset selection with rtmidi: {str(e)}")
            return False, f"Error sending preset selection: {str(e)}"

    @staticmethod
    def is_midi_available() -> bool:
        """Check if MIDI functionality is available on the system"""
        logger.info("Checking if MIDI functionality is available...")

        # Check if rtmidi is available
        if rtmidi is None:
            logger.error("rtmidi module is not available")
            return False

        try:
            # Try to create MIDI input and output objects using python-rtmidi API
            try:
                midi_in = rtmidi.MidiIn()
                midi_out = rtmidi.MidiOut()
            except AttributeError:
                logger.error("rtmidi module does not have MidiIn or MidiOut attributes")
                return False

            # Get available ports using python-rtmidi API
            in_ports = [midi_in.get_port_name(i) for i in range(midi_in.get_port_count())]
            out_ports = [midi_out.get_port_name(i) for i in range(midi_out.get_port_count())]

            # Check if any ports are available
            has_ports = len(in_ports) > 0 or len(out_ports) > 0

            if has_ports:
                logger.info("MIDI functionality is available")
                logger.debug(
                    f"Found {len(in_ports)} input ports and {len(out_ports)} output ports"
                )
            else:
                logger.warning("No MIDI ports found on the system")

            return True  # rtmidi is available even if no ports are found
        except Exception as e:
            logger.error(f"Error checking MIDI functionality: {str(e)}")
            return False

    @staticmethod
    def is_sendmidi_installed() -> bool:
        """
        Check if MIDI functionality is available on the system

        This method is deprecated and has been replaced with python-rtmidi.
        It's kept for backward compatibility and now checks python-rtmidi availability.
        """
        logger.info("is_sendmidi_installed is deprecated, using python-rtmidi directly")
        return MidiUtils.is_midi_available()

    @staticmethod
    async def asend_midi_command(
        command: str, sequencer_port: Optional[str] = None
    ) -> Tuple[bool, str]:
        """
        Asynchronously execute MIDI command using python-rtmidi and optionally send to sequencer port

        This is an async wrapper around send_midi_command for use with FastAPI
        This method is kept for backward compatibility.

        Args:
            command: The MIDI command to execute (in legacy sendmidi format for backward compatibility)
            sequencer_port: Optional sequencer port to send the command to

        Returns:
            Tuple of (success, message)
        """
        logger.info(f"Executing MIDI command asynchronously: {command}")
        try:
            # Get the current event loop
            loop = asyncio.get_event_loop()

            # Run the synchronous send_midi_command in a thread pool
            result = await loop.run_in_executor(
                None, lambda: MidiUtils.send_midi_command(command, sequencer_port)
            )

            return result
        except Exception as e:
            logger.error(f"Unexpected error in asend_midi_command: {str(e)}")
            return False, f"Unexpected error in asend_midi_command: {str(e)}"

    @staticmethod
    async def asend_preset_select(
        port_name: str,
        channel: int,
        pgm_value: int,
        cc_value: int = 0,
        cc_number: int = 0,
        sequencer_port: Optional[str] = None,
    ) -> Tuple[bool, str]:
        """
        Asynchronously send preset selection MIDI messages using python-rtmidi

        This is an async wrapper around send_preset_select for use with FastAPI

        Args:
            port_name: MIDI output port name
            channel: MIDI channel (1-16)
            pgm_value: Value for Program Change (0-127)
            cc_value: Value for CC (0-127), defaults to 0
            cc_number: CC number (0-127), defaults to 0 (Bank Select)
            sequencer_port: Optional sequencer port to send the command to

        Returns:
            Tuple of (success, message)
        """
        logger.info(
            f"Sending preset select asynchronously: port={port_name}, channel={channel}, cc{cc_number}={cc_value}, pgm={pgm_value}"
        )
        try:
            # Get the current event loop
            loop = asyncio.get_event_loop()

            # Run the synchronous send_preset_select in a thread pool
            result = await loop.run_in_executor(
                None,
                lambda: MidiUtils.send_preset_select(
                    port_name, channel, pgm_value, cc_value, cc_number
                ),
            )

            # If sequencer port is specified, send to that port as well
            if (
                sequencer_port and result[0]
            ):  # Only send to sequencer if first send was successful
                logger.info(f"Sending to sequencer port: {sequencer_port}")
                try:
                    seq_result = await loop.run_in_executor(
                        None,
                        lambda: MidiUtils.send_preset_select(
                            sequencer_port, channel, pgm_value, cc_value, cc_number
                        ),
                    )

                    if not seq_result[0]:
                        logger.error(
                            f"Error sending to sequencer port: {seq_result[1]}"
                        )
                        return (
                            False,
                            f"Error sending to sequencer port: {seq_result[1]}",
                        )
                    else:
                        logger.info(
                            f"Successfully sent to sequencer port: {sequencer_port}"
                        )
                except Exception as e:
                    logger.error(f"Error sending to sequencer port: {str(e)}")
                    # Continue execution even if sequencer command fails
                    # Just log the error but don't fail the whole operation

            return result
        except Exception as e:
            logger.error(f"Unexpected error in asend_preset_select: {str(e)}")
            return False, f"Unexpected error in asend_preset_select: {str(e)}"
