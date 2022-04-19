/*
!=================================================================================================================================
! Copyright (c) 2016  Prof. Claus-Dieter Munz
! This file is part of FLEXI, a high-order accurate framework for numerically solving PDEs with discontinuous Galerkin methods.
! For more information see https://www.flexi-project.org and https://nrg.iag.uni-stuttgart.de/
!
! FLEXI is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License
! as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
!
! FLEXI is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
! of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License v3.0 for more details.
!
! You should have received a copy of the GNU General Public License along with FLEXI. If not, see <http://www.gnu.org/licenses/>.
!=================================================================================================================================
*/

#ifndef VISUREADER_H
#define VISUREADER_H

#include <vtkUnstructuredGridAlgorithm.h>
#include <cstring>
#include <algorithm>
#include <iostream>
#include <vector>

#include <vtkMPI.h>
#include <vtkMPICommunicator.h>
#include <vtkMPIController.h>

#include <vtkDataArraySelection.h>
#include <vtkCallbackCommand.h>
#include <vtkSmartPointer.h>

#include <vtkStringArray.h>

#include <../../pluginTypes_visu.h>

#include <vtkIOParallelModule.h> // For export macro
#include <vtkMultiBlockDataSetAlgorithm.h>

// MPI
class vtkMultiProcessController;
// MPI

class VTKIOPARALLEL_EXPORT visuReader :  public vtkMultiBlockDataSetAlgorithm
{
   public:
      vtkTypeMacro(visuReader,vtkMultiBlockDataSetAlgorithm);

      static visuReader *New();

      // macros to set GUI changes to variables
      // gui interaction
      vtkSetStringMacro(FileName);
      vtkSetStringMacro(MeshFileOverwrite);
      vtkSetMacro(NVisu,int);
      vtkSetMacro(NCalc,int);
      vtkSetMacro(UseD3,int);
      vtkSetMacro(HighOrder,int);
      vtkSetMacro(UseCurveds,int);
      vtkSetStringMacro(NodeTypeVisu);
      vtkSetMacro(Avg2d,int);
      vtkSetMacro(DGonly,int);

      // Adds names of files to be read. The files are read in the order they are added.
      void AddFileName(const char* fname);

      // Remove all file names.
      void RemoveAllFileNames();

      vtkSetStringMacro(ParameterFileOverwrite);

      int GetNumberOfVarArrays();
      const char* GetVarArrayName(int index);
      int GetVarArrayStatus(const char* name);
      void SetVarArrayStatus(const char* name, int status);
      void DisableAllVarArrays();
      void EnableAllVarArrays();

      int GetNumberOfBCArrays();
      const char* GetBCArrayName(int index);
      int GetBCArrayStatus(const char* name);
      void SetBCArrayStatus(const char* name, int status);
      void DisableAllBCArrays();
      void EnableAllBCArrays();

      int GetNumberOfVarParticleArrays();
      const char* GetVarParticleArrayName(int index);
      int GetVarParticleArrayStatus(const char* name);
      void SetVarParticleArrayStatus(const char* name, int status);
      void DisableAllVarParticleArrays();
      void EnableAllVarParticleArrays();

      // MPI
      void SetController(vtkMultiProcessController *);
      vtkGetObjectMacro(Controller, vtkMultiProcessController);
      // MPI

      void ConvertToFortran(char* fstring, const char* cstring);

      // struct to exchange arrays between fortran and C
      struct DoubleARRAY coords_DG;
      struct DoubleARRAY values_DG;
      struct IntARRAY  nodeids_DG;
      struct IntARRAY  globalnodeids_DG;
      struct IntARRAY  globalcellids_DG;
      struct DoubleARRAY coords_FV;
      struct DoubleARRAY values_FV;
      struct IntARRAY  nodeids_FV;
      struct IntARRAY  globalnodeids_FV;
      struct IntARRAY  globalcellids_FV;
      struct CharARRAY varnames;
      struct DoubleARRAY coordsSurf_DG;
      struct DoubleARRAY valuesSurf_DG;
      struct IntARRAY  nodeidsSurf_DG;
      struct IntARRAY  globalnodeidsSurf_DG;
      struct IntARRAY  globalcellidsSurf_DG;
      struct DoubleARRAY coordsSurf_FV;
      struct DoubleARRAY valuesSurf_FV;
      struct IntARRAY  nodeidsSurf_FV;
      struct IntARRAY  globalnodeidsSurf_FV;
      struct IntARRAY  globalcellidsSurf_FV;
      struct CharARRAY varnamesSurf;
      struct DoubleARRAY coords_Part;
      struct DoubleARRAY values_Part;
      struct IntARRAY  nodeids_Part;
      struct CharARRAY varnames_Part;
      struct IntARRAY components_Part;
      struct DoubleARRAY coords_Impact;
      struct DoubleARRAY values_Impact;
      struct IntARRAY  nodeids_Impact;
      struct CharARRAY varnames_Impact;
      struct IntARRAY components_Impact;

      int RequestInformation(vtkInformation *, vtkInformationVector **, vtkInformationVector *);
      int RequestData(vtkInformation *, vtkInformationVector **, vtkInformationVector *);

      void InsertData  (vtkMultiBlockDataSet* mb,          int blockno
                      , struct DoubleARRAY* coords,        struct DoubleARRAY* values
                      , struct IntARRAY*    nodeids,       struct IntARRAY* globalnodeids
                      , struct IntARRAY*    globalcellids, struct CharARRAY* varnames);
#if USE_PARTICLES
      /* virtual void InsertPartData(vtkPolyData* mb_part, int blockno, struct DoubleARRAY* coords,
            struct DoubleARRAY* values, struct IntARRAY* nodeids, struct CharARRAY* varnames, struct IntARRAY* components); */
			virtual void InsertPartData(vtkMultiBlockDataSet* mb_part, int blockno, struct DoubleARRAY* coords,
            struct DoubleARRAY* values, struct IntARRAY* nodeids, struct CharARRAY* varnames, struct IntARRAY* components);
#endif

      void DistributeData(vtkMultiBlockDataSet* mb, int blockno);

      vtkDataArraySelection* VarDataArraySelection;
      vtkDataArraySelection* BCDataArraySelection;
      vtkDataArraySelection* VarParticleDataArraySelection;

      // The observer to modify this object when the array selections are modified.
      vtkCallbackCommand* SelectionObserver;

      // Callback registered with the SelectionObserver.
      static void SelectionModifiedCallback(vtkObject* caller, unsigned long eid,
            void* clientdata, void* calldata);


      char* FileName;
      int   NVisu;
      int   NCalc;
      int   UseD3;
      int   HighOrder;
      int   UseCurveds;
      char* NodeTypeVisu;
      int   Avg2d;
      int   DGonly;
      char* ParameterFileOverwrite;
      char* MeshFileOverwrite;
      std::vector<bool> VarNames_selected;
      std::vector<bool> BCNames_selected;
      std::vector<bool> PartNames_selected;
      int NumProcesses;
      int ProcessId;

      // all loaded filenames, timesteps (multiple for timeseries)
      std::vector<std::string> FileNames;
      std::vector<double> Timesteps;

      int FindClosestTimeStep(double requestedTimeValue);

      //void SetNodeTypeVisu(const char* nodetypevisu);
      vtkStringArray* GetNodeTypeVisuList();

   protected:
      visuReader();
      ~visuReader();

      virtual int FillOutputPortInformation(int port, vtkInformation* info);

   private:
      // MPI
      vtkMultiProcessController *Controller;
      MPI_Comm mpiComm;
};

#endif //VISUREADER_H
