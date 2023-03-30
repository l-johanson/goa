namespace eval ::Build::Linux {

        variable rom_modules { }
        variable runtime_archives { }
        variable runtime_config { }

        proc _get_config { runtime_file } {
                set config ""
                catch {
                        set config [query_node /runtime/config $runtime_file]
                        set config [desanitize_xml_characters $config]
                }
                return $config
        }

        proc _get_config_route { runtime_file } {
                set config_route ""
                catch {
			set rom_name [query_attr /runtime config $runtime_file]
			append config_route "\n\t\t\t\t\t" \
			       "<service name=\"ROM\" label=\"config\"> " \
			       "<parent label=\"$rom_name\"/> " \
			       "</service>"
                }
                return $config_route
        }

        proc _get_init_provided_sessions { runtime_file } {
                set sessions ""
                catch {
                        set sessions [query_attrs /runtime/config/parent-provides/service name $runtime_file]
                }
                return $sessions
        }

        proc validate { runtime_file } {
                set config [_get_config $runtime_file]
                set config_route [_get_config_route $runtime_file]

                if {$config != "" && $config_route != ""} {
			exit_with_error "runtime config is ambiguous," \
					"specified as 'config' attribute as well as '<config>' node" }

                if {$config == "" && $config_route == ""} {
			exit_with_error "runtime lacks a configuration\n" \
					"\n You may declare a 'config' attribute in the <runtime> node, or" \
					"\n define a <config> node inside the <runtime> node.\n" }

                set valid_config_sessions {ROM PD RM CPU LOG Gui Gpu Timer Rtc Report File_system Usb Nic}
                set config_sessions [_get_init_provided_sessions $runtime_file]
                set invalid_config_sessions {}
                foreach item $config_sessions {
                    if {$item in $valid_config_sessions} continue
                    exit_with_error "Unsupported service for linux runtime in <parent-provides> node: $item"
                }
        }


	proc bind { runtime_file project_name run_dir var_dir } {
		variable runtime_archives
                variable rom_modules
                variable runtime_config

		set ram    [try_query_attr_from_runtime ram]
		set caps   [try_query_attr_from_runtime caps]
		set binary [try_query_attr_from_runtime binary]

                validate $runtime_file

                set config [_get_config $runtime_file]
                set config_route [_get_config_route $runtime_file]

		set gui_config_nodes ""
		set gui_route        ""
		catch {
			set capture_node ""
			set event_node ""
			catch {
				set capture_node [query_node /runtime/requires/capture $runtime_file]
			}
			catch {
				set event_node   [query_node /runtime/requires/event $runtime_file]
			}
			if {$capture_node == "" && $event_node == ""} {
				set gui_node [query_node /runtime/requires/gui $runtime_file] }

			append gui_config_nodes {

				<start name="drivers" caps="1000">
					<resource name="RAM" quantum="32M" constrain_phys="yes"/>
					<binary name="init"/>
					<route>
						<service name="ROM" label="config"> <parent label="drivers.config"/> </service>
						<service name="Timer">   <child name="timer"/> </service>
						<service name="Capture"> <child name="nitpicker"/> </service>
						<service name="Event">   <child name="nitpicker"/> </service>
						<any-service> <parent/> </any-service>
					</route>
				</start>

				<start name="report_rom" caps="100">
					<resource name="RAM" quantum="1M"/>
					<provides> <service name="Report"/> <service name="ROM"/> </provides>
					<config verbose="no">
						<policy label_prefix="focus_rom" report="nitpicker -> hover"/>
					</config>
					<route>
						<service name="PD">  <parent/> </service>
						<service name="CPU"> <parent/> </service>
						<service name="LOG"> <parent/> </service>
						<service name="ROM"> <parent/> </service>
					</route>
				</start>

				<start name="focus_rom" caps="100">
					<binary name="rom_filter"/>
					<resource name="RAM" quantum="1M"/>
					<provides> <service name="ROM"/> </provides>
					<config>
						<input name="hovered_label" rom="hover" node="hover">
							<attribute name="label" />
						</input>
						<output node="focus">
							<attribute name="label" input="hovered_label"/>
						</output>
					</config>
					<route>
						<service name="ROM" label="hover"> <child name="report_rom"/> </service>
						<service name="PD">  <parent/> </service>
						<service name="CPU"> <parent/> </service>
						<service name="LOG"> <parent/> </service>
						<service name="ROM"> <parent/> </service>
					</route>
				</start>

				<start name="nitpicker" caps="100">
					<resource name="RAM" quantum="4M"/>
					<provides>
						<service name="Gui"/> <service name="Capture"/> <service name="Event"/>
					</provides>
					<route>
						<service name="ROM" label="focus"> <child name="focus_rom"/> </service>
						<service name="PD">  <parent/> </service>
						<service name="CPU"> <parent/> </service>
						<service name="LOG"> <parent/> </service>
						<service name="ROM"> <parent/> </service>
						<service name="Timer">  <child name="timer"/> </service>
						<service name="Report"> <child name="report_rom"/> </service>
					</route>
					<config focus="rom">
						<capture/> <event/>
						<report hover="yes"/>
						<domain name="pointer" layer="1" content="client" label="no" origin="pointer" />
						<domain name="default" layer="2" content="client" label="no" hover="always"/>

						<policy label_prefix="pointer" domain="pointer"/>
						<default-policy domain="default"/>
					</config>
				</start>

				<start name="pointer" caps="100">
					<resource name="RAM" quantum="1M"/>
					<route>
						<service name="PD">  <parent/> </service>
						<service name="CPU"> <parent/> </service>
						<service name="LOG"> <parent/> </service>
						<service name="ROM"> <parent/> </service>
						<service name="Gui"> <child name="nitpicker"/> </service>
					</route>
					<config/>
				</start>
			}

			append gui_route "\n\t\t\t\t\t" \
					 "<service name=\"Gui\"> " \
					 "<child name=\"nitpicker\"/> " \
					 "</service>"
		}

		set capture_route ""
		catch {
			set capture_node [query_node /runtime/requires/capture $runtime_file]

			append capture_route "\n\t\t\t\t\t" \
					     "<service name=\"Capture\"> " \
					     "<child name=\"nitpicker\"/> " \
					     "</service>"
		}

		set event_route ""
		catch {
			set event_route [query_node /runtime/requires/event $runtime_file]

			append event_route "\n\t\t\t\t\t" \
					     "<service name=\"Event\"> " \
					     "<child name=\"nitpicker\"/> " \
					     "</service>"
		}

		set nic_config_nodes ""
		set nic_route        ""
		catch {
			set nic_node [query_node /runtime/requires/nic $runtime_file]
			set nic_label ""
			catch {
				set nic_label [query_node string(/runtime/requires/nic/@label) $runtime_file]
			}

			append nic_config_nodes "\n" {
				<start name="nic_drv" caps="100" ld="no">
					<binary name="linux_nic_drv"/>
					<resource name="RAM" quantum="4M"/>
					<provides> <service name="Nic"/> </provides>}
			if {$nic_label != ""} {
				append nic_config_nodes {
					<config mode="nic_server"> <nic tap="} $nic_label {"/> </config>}
			}
			append nic_config_nodes {
					<route> <any-service> <parent/> </any-service> </route>
				</start>
			}

			append nic_route "\n\t\t\t\t\t" \
				{<service name="Nic"> <child name="nic_drv"/> </service>}
		}

		set uplink_config_nodes ""
		set uplink_provides     ""
		catch {
			set uplink_node [query_node /runtime/requires/uplink $runtime_file]
			set uplink_label ""
			catch {
				set uplink_label [query_node string(/runtime/requires/uplink/@label) $runtime_file]
			}

			append uplink_config_nodes "\n" {
				<start name="nic_drv" caps="100" ld="no">
					<binary name="linux_nic_drv"/>
					<resource name="RAM" quantum="4M"/>
					<provides> <service name="Uplink"/> </provides>}
			if {$uplink_label != ""} {
				append uplink_config_nodes {
					<config mode="uplink_client"> <nic tap="} $uplink_label {"/> </config>}
			}
			append uplink_config_nodes {
					<route>
						<service name="Uplink"> <child name="} $project_name {"/> </service>
						<any-service> <parent/> </any-service>
					</route>
				</start>
			}
			append uplink_provides "\n\t\t\t\t\t" \
				{<service name="Uplink"/>}
		}

		set fs_config_nodes ""
		set fs_routes       ""
		foreach {label writeable} [required_file_systems $runtime_file] {
			set label_fs "${label}_fs"

			append fs_config_nodes {
				<start name="} "$label_fs" {" caps="100" ld="no">
					<binary name="lx_fs"/>
					<resource name="RAM" quantum="1M"/>
					<provides> <service name="File_system"/> </provides>
					<config>
						<default-policy root="/fs/} $label {" writeable="} $writeable {" />
					</config>
					<route>
						<service name="PD">  <parent/> </service>
						<service name="CPU"> <parent/> </service>
						<service name="LOG"> <parent/> </service>
						<service name="ROM"> <parent/> </service>
					</route>
				</start>}

			append fs_routes "\n\t\t\t\t\t" \
				"<service name=\"File_system\" label=\"$label\"> " \
				"<child name=\"$label_fs\"/> " \
				"</service>"

			set fs_dir "$var_dir/fs/$label"
			if {![file isdirectory $fs_dir]} {
				log "creating file-system directory $fs_dir"
				file mkdir $fs_dir
			}
		}

		set rtc_config_nodes ""
		set rtc_route        ""
		catch {
			set rtc_node [query_node /runtime/requires/rtc $runtime_file]

			append rtc_config_nodes "\n" {
				<start name="rtc_drv" caps="100" ld="no">
					<binary name="linux_rtc_drv"/>
					<resource name="RAM" quantum="1M"/>
					<provides> <service name="Rtc"/> </provides>
					<route> <any-service> <parent/> </any-service> </route>
				</start>}

			append rtc_route "\n\t\t\t\t\t" \
					     "<service name=\"Rtc\"> " \
					     "<child name=\"rtc_drv\"/> " \
					     "</service>"
		}

		append runtime_config {
			<config>
				<parent-provides>
					<service name="ROM"/>
					<service name="PD"/>
					<service name="RM"/>
					<service name="CPU"/>
					<service name="LOG"/>
					<service name="TRACE"/>
				</parent-provides>

				<start name="timer" caps="100">
					<resource name="RAM" quantum="1M"/>
					<provides><service name="Timer"/></provides>
					<route>
						<service name="PD">  <parent/> </service>
						<service name="CPU"> <parent/> </service>
						<service name="LOG"> <parent/> </service>
						<service name="ROM"> <parent/> </service>
					</route>
				</start>

				} $gui_config_nodes \
				  $nic_config_nodes \
				  $uplink_config_nodes \
				  $fs_config_nodes \
				  $rtc_config_nodes {

				<start name="} $project_name {" caps="} $caps {">
					<resource name="RAM" quantum="} $ram {"/>
					<binary name="} $binary {"/>
					<provides>} $uplink_provides {</provides>
					<route>} $config_route $gui_route \
						 $capture_route $event_route \
						 $nic_route $fs_routes $rtc_route {
						<service name="ROM">   <parent/> </service>
						<service name="PD">    <parent/> </service>
						<service name="RM">    <parent/> </service>
						<service name="CPU">   <parent/> </service>
						<service name="LOG">   <parent/> </service>
						<service name="TRACE"> <parent/> </service>
						<service name="Timer"> <child name="timer"/> </service>
					</route>
					} $config {
				</start>
			</config>
		}

		set rom_modules [content_rom_modules $runtime_file]
		lappend rom_modules core ld.lib.so timer init

		if {$gui_config_nodes != ""} {
			lappend rom_modules nitpicker \
					    pointer \
					    fb_sdl \
					    event_filter \
					    drivers.config \
					    event_filter.config \
					    en_us.chargen \
					    special.chargen \
					    report_rom \
					    rom_filter

			lappend runtime_archives "nfeske/src/nitpicker"
			lappend runtime_archives "nfeske/src/report_rom"
			lappend runtime_archives "nfeske/src/rom_filter"
			lappend runtime_archives "nfeske/pkg/drivers_interactive-linux"

		}

		if {$nic_config_nodes != "" || $uplink_config_nodes != ""} {
			lappend rom_modules linux_nic_drv

			lappend runtime_archives "nfeske/src/linux_nic_drv"
		}

		if {$fs_config_nodes != ""} {
			lappend rom_modules lx_fs

			lappend runtime_archives "nfeske/src/lx_fs"

			file link -symbolic "$run_dir/fs" "$var_dir/fs"
		}

		if {$rtc_config_nodes != ""} {
			lappend rom_modules linux_rtc_drv

			lappend runtime_archives "nfeske/src/linux_rtc_drv"
		}

		lappend runtime_archives "nfeske/src/init"
		lappend runtime_archives "nfeske/src/base-linux"
	}


	proc execute { run_dir } {
		set orig_pwd [pwd]
		cd $run_dir
		eval spawn -noecho ./core
		cd $orig_pwd

		set timeout -1
		interact {
			\003 {
				send_user "Expect: 'interact' received 'strg+c' and was cancelled\n";
				exit
			}
			-i $spawn_id
		}
	}
}
