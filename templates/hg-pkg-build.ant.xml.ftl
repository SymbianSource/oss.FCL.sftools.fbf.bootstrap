<?xml version="1.0"?>
<project name="hg-build-gen-xml" default="all" xmlns:hlm="http://www.nokia.com/helium">

<#assign fileset = "" />
<#assign target_depends = "" />
<#assign dollar = "$"/>
<#assign count = 0 />

<#list data as pkg_detail>
    <target name="sf-prebuild-${count}">
        <#if (count > 0) >
            <#assign fileset = "${fileset}" + "," />
        </#if>
        <sequential>
            <delete dir="${ant['build.drive']}${pkg_detail.dst}" failonerror="false"/>
            <mkdir dir="${ant['build.drive']}${pkg_detail.dst}"/>
            <hlm:scm verbose="true" scmUrl="scm:hg:${pkg_detail.source}">
                <hlm:checkout basedir="${ant['build.drive']}${pkg_detail.dst}"/>
                <hlm:tags basedir="${ant['build.drive']}${pkg_detail.dst}" reference="hg.tags.id${dollar}{refid}"/>
                <hlm:update basedir="${ant['build.drive']}${pkg_detail.dst}">
                    <hlm:latestTag pattern="${pkg_detail.tag}">
                        <hlm:tagSet refid="hg.tags.id${dollar}{refid}" />
                    </hlm:latestTag>
                </hlm:update>
            </hlm:scm>
        </sequential>
    </target>
    <#assign fileset = "${fileset}" + "<fileset dir=\"${ant['build.drive']}${pkg_detail.dst}\" includes=\"${pkg_detail.pattern}\"/>" />
    <#assign target_depends = "${target_depends}" + "sf-prebuild-${count}" />
    <#assign count = "${count}" + 1 />
</#list>

    <path id="system.definition.files">
        <fileset dir="${dollar}{sf.common.config.dir}/sysdefs" includes="*.sysdef.xml"/>
        ${fileset}
    </path>

<target name="all" depends="${target_depends}"/>

</project>